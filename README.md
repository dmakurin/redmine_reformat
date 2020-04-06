# Redmine Reformat - A Swiss-Army Knife for Converting Redmine Rich Text Data

[![Build Status](https://travis-ci.com/orchitech/redmine_reformat.svg?branch=master)](https://travis-ci.com/orchitech/redmine_reformat)

Redmine Reformat is a [Redmine](http://www.redmine.org/) plugin providing
a rake task for flexible rich-text field format conversion.

## Prepare and Install

### Database Backup

Either backup your database or clone your Redmine instance completely.
A cloned Redmine instance allows you to compare conversion results with
the original.

### Install

```sh
cd $REDMINE_ROOT
git -C plugins clone https://github.com/orchitech/redmine_reformat.git
bundle install
```
And restart your Redmine.

### Installing Converter Dependencies

If using `TextileToMarkdown` converter, [install pandoc](https://pandoc.org/installing.html).
The other provided converters have no direct dependencies.

## Basic Usage

Current format Textile - convert all rich text to Markdown using the default
`TextileToMarkdown` converter setup:
```sh
rake reformat:convert to_formatting=markdown
```

Dry run:
```sh
rake reformat:convert to_formatting=markdown dryrun=1
```

Parallel processing (Unix/Linux only):
```sh
rake reformat:convert to_formatting=markdown workers=10
```

If already using the `commmon_mark` format patch
(see [#32424](https://www.redmine.org/issues/32424)):
```sh
# convert from textile:
rake reformat:convert to_formatting=common_mark
# convert from Redcarpet's markdown - same command:
rake reformat:convert to_formatting=common_mark
```

Convert to HTML (assuming a hypothetical `html` rich text format):
```sh
convcfg='[{
  "from_formatting": "textile",
  "to_formatting": "html",
  "converters": "RedmineFormatter"
}]'
rake reformat:convert to_formatting=html converters_json="$convcfg"
```

Convert using an external web service through intermediate HTML:
```sh
convcfg='[{
  "from_formatting": "textile",
  "to_formatting": "common_mark",
  "converters": [
    ["RedmineFormatter"],
    ["Ws", "http://localhost:4000/turndown-uservice"]
  ]
}]'
rake reformat:convert to_formatting=common_mark converters_json="$convcfg"
```

Other advanced scenarios are covered below.

## Features

- Conversion can be run on a per-project, per-object and per-field basis.
- Different sets of data can use different conversions - useful if some parts
  of your Redmine use different syntax flavours.
- Supports custom fields, journals and even custom field journals.
- Supports parallel conversion in several processes - especially handy when external
  tools are used (pandoc, web services).
- Transaction safety even for parallel conversion.
- Currently supported converters:
  - `TextileToMarkdown` - a Pandoc-based Textile to Markdown converter. Works on markup
    level. Battle-tested on quarter a million strings. See below for details.
  - `MarkdownToCommonmark` - converts main specifics in old Redmine markdown format
    (Redcarpet) to CommonMark/GFM.
  - `RedmineFormatter` - produces HTML using Redmine's internal formatter. Useful
    when chaining with external converters. See below for details.
  - `Ws` - calls an external web service, providing input in the POST body and
    expecting converted output in the response body.
  - Feel free to submit more :)
- Conversions can be chained - e.g. convert Atlassian Wiki Markup (roughly similar
  to Textile) to HTML and then HTML to Markdown using Turndown.

## Conversion Success Rate and Integrity

`TextileToMarkdown` converter:
- Uses heavy preprocessing using adapted Redmine code, which provides solid
  compatibility compared to plain pandoc usage.
- Tested on a Redmine instance with \~250k strings ranging from tiny comments to large
  wiki pages.
- The objects in source (Textile) and converted (Markdown) instances were
  rendered through HTML GUI, the HTMLs were normalized and diffed with exact
  match ratio of 86% with the default `Redcarpet` Markdown renderer.
- A significant part of the differing outputs are actually fixes of improper
  user syntax. :)
- As `Redcarpet` is obsolete and cannot encode all the rich text constructs,
  better results are expected with the new `CommonMarker` Markdown/GFM
  implementation.
- The majority of differences are because of "garbage-in garbage-out" markup.
- Part of the differences are caused by correcting some typical user mistakes in
  Textile markup, mostly missing empty line after headings.
- The results are indeed subject to rich-text format culture within your teams.
- Please note that 100% match is not even desired, see below for more details.
  We believe that the accuracy is approaching 100% of what's possible to match.

Conversion integrity:
- Guaranteed using database transaction(s) covering whole conversion.
- There are a few places where Redmine does not use `ORDER BY`. The order then
  depends on DB implementation and usually reflects record insertion or
  modification order. The conversion is done in order of IDs, which helps to
  keep the unordered order stable. Indeed, not guaranteed at all.

Parallel processing:
- Data are split in non-overlapping sets and then divided among worker
  processes.
- Each worker is converting its own data subset in its own transaction. After
  successful completion, the worker waits on all other workers to complete
  successfuly before commiting the transaction.
- The ID-ordered conversion is also ensured in parallel processing - each
  transaction has its ID range and transactions are commited on order of
  their ID ranges.

## Advanced Scenarios

Use different converter configurations for certain projects and items:
```json
[{
    "projects": ["syncedfromjira"],
    "items": ["Issue", "JournalDetail[Issue.description]", "Journal"],
    "converters": [
      ["Ws", "http://markup2html.uservice.local:4001"],
      ["Ws", "http://turndown.uservice.local:4000"]
    ]
  }, {
    "from_formatting": "textile",
    "converters": "TextileToMarkdown"
  }
]
```

To convert only a part of the data, use `null` in place of the converter chain:
```json
[{
  "projects": ["myproject"],
  "to_formatting": "common_mark",
  "converters": "TextileToMarkdown"
}, {
  "from_formatting": "textile",
  "to_formatting": "common_mark",
  "converters": null
}]
```

## Provided Converters

For more information on markup converters, see
[Markup Conversion Analysis and Design](doc/markup-conversion.md).

### Configuring Converters

Converters are specified as an array of converter instances.
Each converter instance is specified as an array of converter class
name and contructor arguments.
If there is just one converter, the outer array can be omitted,
e.g. `[["TextileToMarkdown"]]` can be specified as `["TextileToMarkdown"]`.
If such converter has no arguments, it can be specified as a string,
e.g. `"TextileToMarkdown"`.

Please note that removing the argument-encapsulating array leads to
misinterpreting the configuration if there are more converters. E.g.
~~`["RedmineFormatter", ["Ws", "http://localhost:4000"]]`~~ would be
interpreted as a single converter with an array argument. A full
specification is required in such cases, e.g.
`[["RedmineFormatter"], ["Ws", "http://localhost:4000"]]`.

### `TextileToMarkdown`

Usage: `'TextileToMarkdown'`\
Arguments: (none)

`TextileToMarkdown` uses Pandoc for the actual conversion. Before pandoc is called,
the input text is subject to extensive preprocessing, often derived from Redmine
code. Placeholderized parts are later expanded after pandoc conversion.

`TextileToMarkdown` is used in default converter config for source markup
`textile` and target `markdown`.

Although there is some partial parsing, the processing is rather performed
on source level and even some user intentions are recognized:
- First line in tables is treated as a header if all cells are strong / bold.
- Headings are terminated even if there is no blank line after them. This is
  usually a user mistake, often leading to making whole block a heading,
  which is not possible in Markdown.
- Space-indented constructs are less often treated as continuations compared
  to the current Textile parser in Redmine. Again, it is usually a user
  mistake and this was changing over time in Redmine. For example, lists
  were allowed to be space-indented until Redmine 3.4.7.
- Footnote refernces bypass pandoc and reconstructed using the placeholder
  mechanism.
- Unbalanced code blocks are tried to be detected and handled correctly.

Generated Markdown is intended to be as compatible as possible since, so
that it works even with the Redcarpet Markdown renderer. E.g. Markdown tables
are formatted in ASCII Art-ish format, as there were cases wher compacted
tables were not recognized correctly by Redcarpet.

See the test fixtures for more details. We admin the conversion is opinionated
and feel free to submit PRs to make it configurable.

<ins>Further development remarks</ins>: conversion utilizing pandoc became
an enormous beast. The amount of code in the preprocessor is comparable
to the Redmine/Redcloth3 renderer. It would have been better if pandoc
hadn't been involved at all - in terms of code complexity, speed and
external dependencies.

### `MarkdownToCommonmark`

Usage: `['MarkdownToCommonmark', options]`\
Arguments:
- `options` - a hash with optional parameters:
  - `hard_wrap`: make hard line breaks from soft breaks, default `true`.
  - `underline`: transform underscore underlines to `<ins>` tags,
    default `true`.
  - `superscript`: transform Redcarpet's caret superscripts to `<sup>`
    tags, default `true`.

`MarkdownToCommonmark` edits the source text to patch the differences
between Redmine Redcarpet format (called `markdown`) and the new
`common_mark` format.

It parses the document with `commonmarker` (the library under the new
`commmon_mark` format), assuming the basic overall structure is the same.
It then walks the document tree and locates source positions to be edited.
It is important to point out that the resulting document is not a
result of a parse&render process, it is always the original document with
some edits.

The `hard_wrap` and `underline` replacements are quite simple, as they
directly follow the document model provided by `commonmarker`.

The `superscript` processing is far more tricky, as it does not have
any document-forming counterpart in CommonMark/GFM. `commonmarker`
is used to locate carets in the right document contexts and the rest
of the processing follows reverse-engineered Redcarpet code.

Macros are preserved by this converter. It also supports macros
with text, which is preserved by default. The `collapse` macro has its
text converted.

### `RedmineFormatter`

Usage: `['RedmineFormatter', options]`\
Arguments:
- `options` - a hash with optional parameters:
  - `macros` - action to perform on Redmine macros:
    - `keep` outputs the macros unmodified. Eventual macro text body is
      subject to rendering. This is the default.
    - `encode` uses encoding that should render to
      `<code>[!]{{</code><code>macro body encoded as JSON string</code><code>}}</code>`
      in the output. This sequence protects the macro and should be easily
      detectable by subsequent parsers. The JSON-encoded string is always
      delimited in quotes (`"`) and it is encoded in a way that it does
      not contain any whitespace.
      You need to decode it to get the original macro name, arguments,
      parameters and text body.
      This also means that even macros like `collapse` that accept a
      text body to be rendered, are not rendered in this mode.
      Makes sense to implement this in the future.

`RedmineFormatter` uses monkey-patched internal Redmine renderer -
`textilizable()`. It converts any format supported by Redmine to
HTML in the same ways as Redmine does it. The monkey patch blocks
macro expansion and keeps wiki links untouched.

### `Ws`

Usage: `['Ws', '<url>']`\
Arguments:
- `url` - address of the web service that performs conversion.

`Ws` performs HTTP POST request to the given URL and passess
text to convert in the request body. The result is expected in the
response body. This allows fast and easy integration with converters
in different programming languages on various platforms.

### `Log`

Usage: `['Log', options]`\
Arguments:
- `options` - a hash with optional parameters:
  - `text_re`: regexp string for text to be matched
  - `reference_re`: regexp string for references to be matched
  - `print`: what from the matched text should be printed:
    -  `none` - reference only, no text
    -  `first` - also print first match of the text
    -  `all` - also print all matches of the text

`Log` logs what is going through the converter chain. Useful for
debugging or searching for specific syntax within rich text data.
The converter hands over the input as is.

## Reformat Microservice

For certain integration and testing use cases, it might be useful to expose
the converter engine for use of external services. `redmine_reformat` provides
a simple HTTP service for this purpose in the `reformat:microservice` rake
task. The setup is very similar to the `reformat:convert` rake task.

```
rake reformat:microservice from_formatting=common_mark
Running with setup:
{:converters_json=>"(use default converters)",
 :to_formatting=>nil,
 :workers=>1,
 :port=>3030,
 :from_formatting=>"common_mark"}
[2020-03-27 22:53:16] INFO  WEBrick 1.4.2
[2020-03-27 22:53:16] INFO  ruby 2.6.5 (2019-10-01) [x86_64-linux]
[2020-03-27 22:53:16] INFO  WEBrick::HTTPServer#start: pid=5343 port=3030
(CTRL+C or TERM signal closes the server)
```

In the example above, visit `http://localhost:3030` to get more info on usage.

The microservice works as follows:
- Instead of reading texts and writing them to the database, it takes them
  from HTTP POST request and returns converted text as a response body.
- Context variables for eventual filtering and logging can be provided as
  query parameters. That is `from_formatting`, `to_formatting`, `item`, `id`,
  `project_id` and `ref`. If not provided, safe defaults are used.
- `from_formatting` and `to_formatting` are required either as a default
  in the rake task environment or as a query parameter. This differs from
  `reformat:convert`, which takes defaults from current Redmine's settings.
- The `workers` variable is currently ignored.
- There is an extra attribute `port` with obvious meaning.

## History

The project has its origins in Textile to Markdown conversion scripts and
plugins for Redmine. Although there is not much of any original code left,
we really value the community contributions of our predecessors.

1. `convert_textile_to_markdown` script was built upon @sigmike
   [answer on Stack Overflow](http://stackoverflow.com/a/19876009)
2. later [slightly modified by Hugues C.](http://www.redmine.org/issues/22005)
3. Completed by Ecodev and
   [published on GitHub](https://github.com/Ecodev/redmine_convert_textile_to_markown).
4. Significantly improved by Planio / Jens Krämer:
   [GitHub fork](https://github.com/planio-gmbh/redmine_convert_textile_to_markown)
5. Conversion rewritten by Orchitech and created the conversion framework
   `redmine_reformat`. Released under GPLv3.
