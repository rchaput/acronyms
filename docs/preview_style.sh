#!/bin/sh

# This a helper script to preview a style.
# It can be used with `./preview_style.sh <style>`, where `<style>` is one of
# the acronyms' styles (such as: "short-long", "long-long", ...).
# It was made to be used as part of Quarto documents, to create all previews
# automatically when building the documentation website.


# The filter is at `_extensions/acronyms/parse-acronyms.lua`, from the root dir.
# However, we do not know exactly which current working dir will be used
# (depending on whether we run this script manually or from a Quarto document).
# Thus, we need to obtain the path to the filter, relatively to this script.
docs_dir=$(dirname "$0")
path_to_filter="${docs_dir}/../_extensions/acronyms/"


# We require the `style` parameter (do not care about other arguments...)
if [ "$#" -lt 1 ]; then
  echo >&2 "Error in $0: missing required argument 'style'!"
  exit 1
fi
# If the Lua filter cannot be found, we have a problem
if [ ! -d "$path_to_filter" ]; then
  echo >&2 "Error in $0: filter $path_to_filter ($(realpath "$path_to_filter")) does not exist!"
  exit 2
fi
# We need pandoc, but the error if it is not found is not very clear in knitr
if ! type pandoc >/dev/null; then
  echo >&2 "Error in $0: pandoc not found!"
  exit 3
fi


# Remember the current directory so we can cd back to it after.
# We need to cd to the extensions dir, so that the requires (using, e.g.,
# `require('acronyms_helpers')`) work.
# Quarto automatically sets the path, but we cannot use Quarto here (too
# complicated to point to the correct folder, render a temporary file, etc.).
previous_dir=$(pwd)
cd "${path_to_filter}"


pandoc -t markdown -f markdown --lua-filter="parse-acronyms.lua" <<EOF
---
acronyms:
  keys:
    - shortname: qmd
      longname: Quarto document
  style: $1
  insert_loa: false
  insert_links: false
---
First use: \acr{qmd}

Next uses: \acr{qmd}
EOF

cd "${previous_dir}"
