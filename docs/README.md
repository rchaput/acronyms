This folder contains the documentation for the **acronyms** Quarto extension.

The documentation is itself a Quarto project that builds a website, to be
deployed on GitHub Pages.

*Note*: the `articles/styles.qmd` page requires `knitr` to build!

The following commands all assume that the current working directory is
this project's root. They can also be launched from the `docs/` directory,
in which case all references to `docs` should be removed.

## Build the website

```sh
quarto render docs
```

## Build a single file (to debug)

```sh
quarto render docs/<path/to/desired file>
```

## Live preview

```sh
quarto preview docs
```
