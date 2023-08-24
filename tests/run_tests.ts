// Import the formatting library from the standard lib. Note: it is not
// downloaded from the Internet, but loaded from quarto's embedded stdlib.
// (This is also why we cannot use a versioned URL)
import { sprintf } from "https://deno.land/std/fmt/printf.ts";
import {
    bold,
    red,
    green
} from "https://deno.land/std/fmt/colors.ts";
// We need `ensureSymlinkSync` to create a symlink to the `_extensions` folder
// in the root dir.
import { ensureSymlinkSync } from "https://deno.land/std/fs/mod.ts";
// We need `writeAllSync` to write directly to the console (avoids `\n`).
import { writeAllSync } from "https://deno.land/std/streams/mod.ts";
// We need path manipulations to get the `tests` folder path based on the
// path to the current running script.
import {
    dirname,
    fromFileUrl,
    resolve
} from "https://deno.land/std/path/mod.ts";


interface TestResult {
    name: string;
    success: boolean;
    returnCode: number;
    inputFilePath: string;
    originalOutput: string; // Unfiltered result
    actualOutput: string; // Filtered result to remove Quarto details
    expectedOutput: string;
    originalError: string; // Unfiltered error logs
    actualError: string; // Filtered errors to remove Quarto details
    expectedError: string;
    executionTimeMs: number;
}

// We need this to handle CRLF / LF line separators (thank you Windows...).
const eolRegex = /\r?\n/;
const eol = Deno.build.os === "windows" ? "\r\n" : "\n";


/*
 * This function returns the path to the `tests` folder.
 * It is obtained based on the path to this current script.
 */
function getPathToTestsFolder (): string {
    return dirname(fromFileUrl(import.meta.url));
}


/*
 * Read and return the content of a file, or a default value if the file does
 * not exist.
 */
function readFileOrDefault (filePath: string, defaultValue: string = ''): string {
    try {
        return Deno.readTextFileSync(filePath);
    } catch (err) {
        if (!(err instanceof Deno.errors.NotFound)) {
            throw  err;
        }
        return defaultValue;
    }
}


/*
 * Filter the `stdout` (standard output) of a test, to remove undesired lines.
 * This simplifies the comparison with a known (correct) output.
 */
function filterStdout (stdout: string) {
    // Unfortunately, Quarto renders the YAML metadata inside the md document
    // (when using the `md` format), contrary to "pure" Pandoc.
    // We need to remove these lines to compare the output to the expected one.
    let stdoutLines = stdout.split(eolRegex);
    const metadataStartIndex = stdoutLines.indexOf('---');
    // We want to find the 2nd `'---'` line, i.e., the one after the first!
    const metadataEndIndex = stdoutLines.indexOf('---', metadataStartIndex + 1);
    // We want to take only lines after the last `---` + 2
    // (+2 because we do not want the '---' itself, nor the next blank line).
    stdoutLines = stdoutLines.slice(metadataEndIndex + 2);
    stdout = stdoutLines.join(eol);
    return stdout;
}


/*
 * Filter the `stderr` (standard error) of a test, to remove undesired lines.
 * This simplifies the comparison with a known (expected) error.
 */
function filterStderr (stderr: string) {
    // We want to retrieve the stderr to check for warnings in the acronyms
    // extension. However, Quarto outputs some debug information on stderr...
    // Using `--quiet` removes *all* output on stderr, so we cannot use it.
    // We need to filter out the first lines, which consist of 2 "blocks",
    // indented by 2 spaces (`  `). They end by a line with only these spaces.
    let stderrLines = stderr.split(eolRegex);
    const endOfFirstBlock = stderrLines.indexOf('  ');
    const endOfSecondBlock = stderrLines.indexOf('  ', endOfFirstBlock + 1);
    // Now, take only the lines following these blocks.
    stderrLines = stderrLines.slice(endOfSecondBlock + 1);
    // Remove the line that states that `input.md` was created (+ the following
    // empty line).
    const outputCreatedLine = stderrLines.indexOf('Output created: input.md');
    stderrLines.splice(outputCreatedLine, 2);
    stderr = stderrLines.join(eol);
    return stderr;
}


/*
 * Perform a test on a single folder.
 */
function testSingleDir (dirName: string): TestResult {
    // Absolute path to the `tests` folder (obtained from this current script).
    const testsPath = getPathToTestsFolder();
    // Path to the input file path in the desired folder.
    const inputFilePath = resolve(testsPath, `${dirName}/input.qmd`);
    // Path to output file (in the test folder, same name as input file,
    // but with `.md` extension).
    const outputPath = resolve(testsPath, `${dirName}/input.md`);

    // Create a new process and ask quarto to render the document.
    const command = new Deno.Command(
        'quarto',
        {
            args: [
                'render',
                inputFilePath,
                // Rendering to stdout does not work on Windows until Quarto 1.4,
                // we need to output to a file instead.
                // Using `--output filename` outputs to the current working dir
                // (not what we want); we cannot specify a path in `--output`;
                // using `--output-dir` does not work, because this is not a
                // project. So we have no choice (?) but to leave Quarto create
                // the default file, which has the same name as input, with the
                // `.md` extension.
                // '--output', '-',
            ],
        }
    );

    // Execute the command, and get the return code (0 if success), standard
    // output (the document), and standard error (the errors or warnings log).
    const startTime = performance.now();
    let { code, stderr } = command.outputSync();
    const endTime = performance.now();
    stderr = new TextDecoder().decode(stderr);

    // Read the output
    let stdout = Deno.readTextFileSync(outputPath);
    // Filter the stdout and stderr because Quarto *loves* adding stuff...
    const filteredStdout = filterStdout(stdout);
    const filteredStderr = filterStderr(stderr);

    // The expected output document
    const expectedOutputPath = `tests/${dirName}/expected.md`;
    const expectedOutput = Deno.readTextFileSync(expectedOutputPath);

    // The expected errors / warnings log
    const expectedErrorPath = `tests/${dirName}/expected.stderr`;
    const expectedError = readFileOrDefault(expectedErrorPath, '');

    const success = (code == 0) &&
        (filteredStdout == expectedOutput) &&
        (filteredStderr == expectedError);

    return {
        'name': dirName,
        'success': success,
        'returnCode': code,
        'inputFilePath': inputFilePath,
        'originalOutput': stdout,
        'actualOutput': filteredStdout,
        'expectedOutput': expectedOutput,
        'originalError': stderr,
        'actualError': filteredStderr,
        'expectedError': expectedError,
        'executionTimeMs': endTime - startTime,
    };
}


/*
 * Print a text to the standard output; this a low-level operation.
 * Contrary to `console.log`, it does not append a newline automatically.
 */
function writeToStdout (text: string) {
    const contentBytes = new TextEncoder().encode(text);
    writeAllSync(Deno.stdout, contentBytes);
}


/*
 * Print the result of the tests to Markdown.
 * This is a long output, made to provide details about each test.
 */
function resultToStrMd (results: Array<TestResult>): string {
    let str = '# Automatic tests report\n\n';

    // 1st section: summary table (short, one-line for each test)
    str += '## Summary\n\n';
    str += '| Test | Result | :alarm_clock: Duration (s) |\n';
    str += '|---|---|---|\n';
    for (let result of results) {
        const resultEmoji = result.success ? ':white_check_mark: PASS' : ':x: FAIL';
        const headingSlug = result.name.replace(' ', '-');
        str += sprintf('| [%s](#%s) | %s | %d |\n',
                       result.name,
                       headingSlug,
                       resultEmoji,
                       result.executionTimeMs / 1000);
    }
    str += '\n';

    // 2nd section: current quarto installation (versions, dependencies, ...)
    // Useful to debug, when there is a problem with a test, which version of
    // quarto or pandoc is used, and whether this version is causing the problem.
    // However, the default output contains control characters (e.g., `\r`), so
    // we need to output the log instead to a file, and then read the file...
    const quartoCheckOutputPath = Deno.makeTempFileSync();
    const command = new Deno.Command('quarto', {
        args: ['check', '--quiet', '--log-format', 'plain', '--log', quartoCheckOutputPath],
    });
    command.outputSync();
    const quartoCheckOutput = Deno.readTextFileSync(quartoCheckOutputPath);
    Deno.removeSync(quartoCheckOutputPath);
    str += '## Configuration details\n\n';
    str += '```' + quartoCheckOutput + '```\n\n';

    // 3rd section: detailed results for each test
    for (let result of results) {
        // Result header
        str += sprintf('## %s\n\n', result.name);

        // Return code == 0?
        if (result.returnCode == 0) {
            str += ':white_check_mark: Return code was <span style="color: green">0</span>\n\n';
        } else {
            str += ':x: Return code was <span style="color: red">' + result.returnCode + '</span>\n\n';
        }

        // Output == expected output?
        if (result.actualOutput == result.expectedOutput) {
            str += ':white_check_mark: Output corresponds to expected output:\n';
        } else {
            str += ':x: Output does not correspond to expected output:\n';
        }
        str += `
<details>
<summary>Actual:</summary>

${result.actualOutput.split('\n').map(line => '    ' + line).join('\n')}

</details>

<details>
<summary>Expected:</summary>

${result.expectedOutput.split('\n').map(line => '    ' + line).join('\n')}

</details>

`;

        // Error == expected error?
        if (result.actualError == result.expectedError) {
            str += ':white_check_mark: Error corresponds to expected error:\n';
        } else {
            str += ':x: Error does not correspond to expected error:\n';
        }
        str += `
<details>
<summary>Actual:</summary>

${result.actualError.split('\n').map(line => '    ' + line).join('\n')}

</details>

<details>
<summary>Expected:</summary>

${result.expectedError.split('\n').map(line => '    ' + line).join('\n')}

</details>

`;

        // The input file, for full details; this includes the YAML metdata
        const testInput = Deno.readTextFileSync(result.inputFilePath);
        str += `

:page_with_curl: Details:

<details>
<summary>Input file:</summary>

${testInput.split('\n').map(line => '    ' + line).join('\n')}

</details>

<details>
<summary>Original stdout</summary>

${result.originalOutput.split('\n').map(line => '    ' + line).join('\n')}

</details>

<details>
<summary>Original stderr</summary>

${result.originalError.split('\n').map(line => '    ' + line).join('\n')}

</details>

`;
    }

    return str;
}


const testDirs = [
    '01-simple',
    '02-custom-title',
    '03-no-title',
    '04-replace-duplicates',
    '05-keep-duplicates',
    '06-external-yaml',
    '07-multiple-external-yaml',
    '08-style-short-long',
    '09-style-footnote',
    '10-no-links',
    '11-missing-key',
    '12-missing-unknown',
    '13-insert-loa-end',
    '14-insert-loa-false',
    '15-insert-loa-false-printacronyms',
    '16-not-include-unused',
    '17-sorting-alphabetical',
    '18-sorting-initial',
    '19-sorting-usage',
    '20-sorting-alphabetical-case-insensitive',
    '21-loa-unnumbered-section',
    '22-shortcode-simple',
    '23-shortcode-specific-style',
    '24-shortcode-listofacronyms',
];


function main () : number {
    // Quarto needs to access the `_extensions` folder that is in the project
    // root (the parent folder). We thus ensure that a symbolic link exists
    // (Deno creates it otherwise).
    const testsPath = getPathToTestsFolder();
    ensureSymlinkSync(
        // The target folder at the root folder (parent of `tests).
        resolve(testsPath, '../_extensions'),
        // The desired symlink location, in the `tests` folder.
        resolve(testsPath, '_extensions')
    );

    const testsToPerform = (Deno.args.length == 0) ? testDirs : Deno.args;

    // Run tests, save results, and output regularly to stdout.
    // We want a short report (1 line by test).
    const results = [];
    let nbSuccesses = 0;
    let nbFails = 0;
    for (const test of testsToPerform) {
        // Print a message to keep the user waiting
        writeToStdout('Running test ' + test + ' ...');
        // Run the test and save the result (especially for the md report)
        const result = testSingleDir(test);
        results.push(result);
        if (result.success) nbSuccesses += 1;
        else nbFails += 1;
        // Print the test result to stdout (on the same line)
        const success = result.success ? green(bold('PASS')) : red(bold('FAIL'));
        writeToStdout(' ' + success + '\n');
    }
    // Print short summary
    writeToStdout(sprintf('\nTotal: %d %s / %d %s\n',
                          nbSuccesses, green(bold('PASS')),
                          nbFails, red(bold('FAIL'))));

    // If we are in a GitHub CI, we also want to write a "Job Summary",
    // in the form of a (detailed) Markdown report.
    const githubSummaryPath = Deno.env.get('GITHUB_STEP_SUMMARY');
    if (githubSummaryPath != undefined) {
        const summary = resultToStrMd(results);
        Deno.writeTextFileSync(githubSummaryPath, summary);
    }

    // Return the number of failed tests. This can be used to set the return
    // code of the script. Any value !=0 is considered to be an error.
    return nbFails;
}

const returnCode = main();
Deno.exit(returnCode);
