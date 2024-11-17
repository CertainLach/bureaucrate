//! Changelog generation example

local pc = import './pc.libsonnet';

// TODO: use parsonnet or smth?
local
  capitalize(line) = std.asciiUpper(line[0]) + line[1:],

  // Count amount of empty lines at beginning of array
  countEmptyStart(lines) = if std.length(lines) != 0 && lines[0] == ''
  then 1 + countEmptyStart(lines[1:]) else 0,
  // Remove empty lines at beginning and on end of array
  trimEmptyLines(lines) = lines[countEmptyStart(lines):std.max(std.length(lines) - countEmptyStart(std.reverse(lines)), 0)],

  // Extract all trailers from end of line array
  validTrailers = ['Cc', 'Signed-off-by', 'Reviewed-by', 'Co-authored-by'],
  isTrailerLine(line) = line == '' || std.any(std.map(function(trailer) std.startsWith(line, trailer + ': '), validTrailers)),
  parseTrailers(lines) = if std.length(lines) != 0 && isTrailerLine(lines[0]) then
    [lines[0]] + parseTrailers(lines[1:])
  else [],

  findByPrefix(lines, prefix) =
    local aux(index) =
      if index >= std.length(lines) then null
      else if std.startsWith(lines[index], prefix) then index
      else aux(index + 1);
    aux(0),

  // Split BREAKING CHANGES or other category from line list
  splitCategory(lines, category) =
    local splitIndex = findByPrefix(lines, category);
    if splitIndex == null then { rest: trimEmptyLines(lines), split: null }
    else {
      split: std.join('\n', lines[splitIndex:])[std.length(category):],
      rest: lines[:splitIndex],
    },
  splitBreakingChange(lines) = splitCategory(lines, 'BREAKING CHANGE: '),
  splitProduct(lines) = splitCategory(lines, 'PRODUCT: '),

  // Parse conventional commit header
  validTypes = ['feat', 'fix', 'refactor', 'build', 'ci', 'docs', 'doc', 'test', 'style', 'chore', 'perf'],
  pcl = pc {
    convType: $.capture($.any(std.map($.const, validTypes))),
    optScope: $.optional($.seq(['(', $.capture($.greedy($.any([
      $.alpha,
      '-',
      ' ',
      '_',
    ]))), ')'])),
    optBang: $.apply($.optional($.capture('!')), function(v) v != null),
    header: $.seq([$.convType, $.optScope, $.optBang, ': ', $.capture($.greedy($.charAny()))]),
  },
  parseHeader(rawHeader) =
    local
      replacePrefix(string, from, to) =
        if std.startsWith(string, from) then to + string[std.length(from):]
        else string,
      replacePrefixes(string, replacements) =
        std.foldl(function(string, replacement) replacePrefix(string, replacement[0], replacement[1]), replacements, string),
      header =
        replacePrefixes(rawHeader, [
          ['doc:', 'docs:'],
          ['doc(', 'docs('],
          ['feature:', 'feat:'],
          ['Fix:', 'fix:'],
        ]),
      parsed = pcl.runParser(pcl.header, header);
    if
      std.startsWith(header, 'Merge branch ')
      || std.startsWith(header, 'Merge pull request ')
      || std.startsWith(header, 'Merge remote-tracking branch ')
      || std.startsWith(header, 'fixup!')
      || std.startsWith(header, 'Merge remote-tracking branch ')
    then {
      kind: 'chore',
      scope: null,
      bang: false,
      message: header,
    }
    else if header == 'Add explicit drop() to avoid warning since Rust 1.57.0' then {
      kind: 'chore',
      scope: null,
      bang: false,
      message: header,
    }
    else if header == 'Remove remainder of `codegenerated-stdlib`' then {
      kind: 'refactor',
      scope: null,
      bang: false,
      message: header,
    }
    else if
      header == 'Enable multi-occurences for --jpath + improve positional params error message'
      || header == 'Add std.manifestJsonMinified()'
      || header == 'Import `std.get(o, f, default=null, inc_hidden=true)`'
      || header == 'Add location info to all sub-expressions'
    then {
      kind: 'feat',
      scope: null,
      bang: false,
      message: header,
    }
    else if parsed[1] != null then error 'commit title parse error: %s\ntried to parse: %s\npartial result: %s' % [parsed[1], header, parsed + '']
    else {
      local value = parsed[0],
      kind: value[0],
      scope: value[1],
      bang: value[2],
      message: value[4],
    };

// Standard git commit format parser, split message to header, body and trailers
local parseCommitStandard(commit) = (
  commit {
    local lines = trimEmptyLines(std.split(self.message, '\n')),
    // TODO: handle empty body?
    local body = trimEmptyLines(lines[1:]),
    local trailers = parseTrailers(std.reverse(body)),
    local description = std.join('\n', trimEmptyLines(body[:std.length(body) - std.length(trailers)])),

    header: lines[0],
    description: description,
    trailers: trimEmptyLines(trailers),

    // Hide message, as only parsed parts should be used
    message:: super.message,
    validated:: self,
  }
).validated;

// Parse commit as conventional
local parseCommitConventional(commit) = (
  parseCommitStandard(commit) {
    local descriptionRaw = std.split(super.description, '\n'),
    local breakingChangeRaw = splitBreakingChange(descriptionRaw),
    local productRaw = splitProduct(breakingChangeRaw.rest),
    local description =
      local aux = std.join('\n', productRaw.rest);
      if aux == '' then null else aux,

    header: parseHeader(super.header),
    description: description,
    breaking: breakingChangeRaw.split,
    product: productRaw.split,

    validated::
      assert (self.breaking == null || self.header.bang) || (!self.header.bang || self.breaking != null) : 'bang should be present only when breaking is set, and vice-versa';
      self,

    message:: super.message,
  }
).validated;

local commitHandler(commits) =
  local
    parsedCommits = std.map(parseCommitConventional, commits),
    hasBreaking = std.any(std.map(function(c) c.breaking != null, parsedCommits)),
    hasFeatures = std.any(std.map(function(c) c.header.kind == 'feat', parsedCommits)),
    hasOtherChanges = std.length(parsedCommits) != 0,
    product = std.filter(function(p) p != null, std.map(function(c) c.product, parsedCommits)),
    breaking = std.filter(function(p) p != null, std.map(function(c) c.breaking, parsedCommits)),

    commitsOfKind(kind, desc=null) = std.filter(function(c) c.header.kind == kind && (
      if desc == null then true
      else if desc == true then c.description != null
      else if desc == false then c.description == null
      else error 'bad desc filter: ' + desc
    ), parsedCommits),

    // TODO: should we have special formatting for commit ids, i.e wrap them to correct
    features = std.map(function(c) '### %s %s\n\n%s' % [capitalize(c.header.message), c.id, c.description], commitsOfKind('feat', true)),
    otherFeatures = std.map(function(c) '- %s %s' % [capitalize(c.header.message), c.id], commitsOfKind('feat', false)),
    fixes = std.map(function(c) '- %s %s%s' % [capitalize(c.header.message), c.id, if c.description != null then '\n\n' + c.description else ''], commitsOfKind('fix')),
    otherChanges = std.map(function(c) '- %s: %s %s%s' % [c.header.kind, capitalize(c.header.message), c.id, if c.description != null then '\n\n' + c.description else ''], std.filter(function(c) c.header.kind != 'feat' && c.header.kind != 'fix', parsedCommits)),

    productSection = if std.length(product) != 0 then |||
      ## Product changes

      %s

    ||| % std.join('\n\n', std.map(function(p) '- ' + p, product)) else '',
    breakingSection = if std.length(breaking) != 0 then |||
      ## Breaking changes

      %s

    ||| % std.join('\n\n', std.map(function(p) '- ' + p, breaking)) else '',
    featuresSection = if std.length(features) != 0 then |||
      ## Added features

      %s

    ||| % std.join('\n\n', std.map(function(p) p, features)) else '',
    otherFeaturesSection = if std.length(otherFeatures) != 0 then |||
      ## %s

      %s

    ||| % [if featuresSection != '' then 'Other features' else 'Added features', std.join('\n\n', std.map(function(p) p, otherFeatures))] else '',
    fixesSection = if std.length(fixes) != 0 then |||
      ## Bugfixes

      %s

    ||| % std.join('\n\n', std.map(function(p) p, fixes)) else '',
    otherSection = if std.length(otherChanges) != 0 then |||
      ## Other changes

      %s

    ||| % std.join('\n\n', std.map(function(p) p, otherChanges)) else '';

  {
    changelog: productSection + breakingSection + featuresSection + otherFeaturesSection + fixesSection + otherSection,
    // Changelog generator may decide to bump package versions
    //  0 - no bump required
    //  1 - patch bump
    //  2 - minor bump
    //  3 - major bump
    bump:
      if hasBreaking then 3
      else if hasFeatures then 2
      // TODO: do not bump version if there is only `ci:`/`style:` changes?
      else if hasOtherChanges then 1
      else 0,
  }

;  // commitHandler

{
  commitHandler:: commitHandler,
}
