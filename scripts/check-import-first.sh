#!/usr/bin/env bash
# check-import-first.sh — enforce the IMPORT-FIRST golden rule statically.
#
# Every managed `resource "<type>" "<name>"` block in *.tf MUST carry one of:
#   1. a matching `import { ... to = <type>.<name> ... }` block — the
#      under-management proof, kept PERMANENTLY (a no-op once the object is in
#      state); or
#   2. an explicit, reviewed escape-hatch marker on the line directly above the
#      resource, for a genuinely NEW object the network does not have yet:
#        # import-first:new <why this object does not exist yet>
#
# Why a permanent import block: tofu-controller owns state in-cluster, this repo
# ships no state, and `tofu import` via the CLI leaves no trace in *.tf. Keeping
# the `import {}` block is the only static, self-documenting proof a resource is
# already under management rather than about to be CREATED on first apply.
#
# Usage: check-import-first.sh [DIR]   (DIR defaults to the current directory)
# Exits non-zero and lists the offenders when the rule is violated.
set -Eeuo pipefail

dir="${1:-.}"

if [ ! -d "$dir" ]; then
  printf 'error: not a directory: %s\n' "$dir" >&2
  exit 2
fi

# Collect *.tf files (NUL-safe; bash 3.2 compatible — no `mapfile -d`).
tf_files=()
while IFS= read -r -d '' f; do
  tf_files+=("$f")
done < <(find "$dir" -type f -name '*.tf' -not -path '*/.terraform/*' -print0)

if [ "${#tf_files[@]}" -eq 0 ]; then
  printf '✅ import-first guard: no .tf files to check.\n'
  exit 0
fi

# AWK strips comments (line `#`/`//` and block `/* */`), then records every
# uncommented resource address, every uncommented import target, and which
# resources carry the escape-hatch marker. It prints "FAIL <addr> <file>:<line>"
# for each managed resource lacking both an import block and a marker.
violations="$(
  awk '
    FNR == 1 { inblock = 0; inimport = 0; pending_marker = 0; bdepth = 0 }
    {
      raw  = $0
      code = raw

      # finish an open /* ... */ block comment
      if (inblock) {
        idx = index(code, "*/")
        if (idx == 0) { next }
        code = substr(code, idx + 2)
        inblock = 0
      }

      # escape-hatch marker (checked on the raw comment line, before stripping)
      if (raw ~ /^[[:space:]]*#[[:space:]]*import-first:new([[:space:]]|$)/) {
        pending_marker = 1
        next
      }

      # strip inline /* ... */ blocks (and open an unterminated one)
      while ((s = index(code, "/*")) > 0) {
        rest = substr(code, s + 2)
        e = index(rest, "*/")
        if (e == 0) { code = substr(code, 1, s - 1); inblock = 1; break }
        code = substr(code, 1, s - 1) substr(rest, e + 2)
      }

      # strip line comments (# and //)
      h = index(code, "#");  if (h > 0) code = substr(code, 1, h - 1)
      d = index(code, "//"); if (d > 0) code = substr(code, 1, d - 1)

      # import-block tracking — capture every `to = <address>`
      if (code ~ /^[[:space:]]*import[[:space:]]*\{/) { inimport = 1; bdepth = 0 }
      if (inimport) {
        if (match(code, /to[[:space:]]*=[[:space:]]*[A-Za-z0-9_.[\]"-]+/)) {
          tgt = substr(code, RSTART, RLENGTH)
          sub(/^to[[:space:]]*=[[:space:]]*/, "", tgt)
          sub(/\[.*$/, "", tgt)             # drop any [index] / [for_each key]
          imports[tgt] = 1
        }
        tmp = code
        o = gsub(/[{]/, "&", tmp)
        c = gsub(/[}]/, "&", tmp)
        bdepth += o - c
        if (bdepth <= 0) inimport = 0
      }

      # resource declaration
      if (match(code, /^[[:space:]]*resource[[:space:]]+"[^"]+"[[:space:]]+"[^"]+"/)) {
        line2 = code
        match(line2, /"[^"]+"/); rtype = substr(line2, RSTART + 1, RLENGTH - 2)
        line2 = substr(line2, RSTART + RLENGTH)
        match(line2, /"[^"]+"/); rname = substr(line2, RSTART + 1, RLENGTH - 2)
        n_res++
        res_addr[n_res]   = rtype "." rname
        res_file[n_res]   = FILENAME
        res_line[n_res]   = FNR
        res_marked[n_res] = pending_marker
        pending_marker = 0
        next
      }

      # any other non-blank code line cancels a pending marker
      if (code ~ /[^[:space:]]/) pending_marker = 0
    }
    END {
      for (i = 1; i <= n_res; i++) {
        if (res_marked[i]) continue
        if (res_addr[i] in imports) continue
        printf "FAIL %s %s:%d\n", res_addr[i], res_file[i], res_line[i]
      }
    }
  ' "${tf_files[@]}"
)"

if [ -n "$violations" ]; then
  {
    printf '❌ import-first guard: these managed resources have no matching\n'
    printf '   import {} block and no reviewed "# import-first:new" marker:\n\n'
    while IFS=' ' read -r _tag addr loc; do
      [ -n "$addr" ] || continue
      printf '   • %s  (%s)\n' "$addr" "$loc"
    done <<< "$violations"
    printf '\nFix: add an import block proving it is already under management —\n'
    printf '     import { to = <type>.<name>  id = "<controller-id>" }\n'
    printf '   or, for a genuinely NEW object, put a reviewed marker above it:\n'
    printf '     # import-first:new <why this object does not exist yet>\n'
  } >&2
  exit 1
fi

printf '✅ import-first guard: every managed resource carries an import block or marker.\n'
