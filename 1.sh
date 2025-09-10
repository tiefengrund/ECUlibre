git apply -p0 <<'PATCH'
diff --git a/.github/workflows/ci-arch.yml b/.github/workflows/ci-arch.yml
--- a/.github/workflows/ci-arch.yml
+++ b/.github/workflows/ci-arch.yml
@@
 name: CI (Arch)
 on:
   push:
-    branches: [ "main" ]
+    branches: [ "master" ]
   pull_request:
   workflow_dispatch:
 permissions: { contents: read }
diff --git a/.github/workflows/ci-core.yml b/.github/workflows/ci-core.yml
--- a/.github/workflows/ci-core.yml
+++ b/.github/workflows/ci-core.yml
@@
 name: CI (core)
 on:
   push:
-    branches: [ "main" ]
+    branches: [ "master" ]
   pull_request:
   workflow_dispatch:
@@
           base: ${{ github.ref_name || 'main' }}
+          # Hinweis: falls euer Default-Branch "master" ist, ist github.ref_name dort meist "master".
diff --git a/.github/workflows/ci-suse.yml b/.github/workflows/ci-suse.yml
--- a/.github/workflows/ci-suse.yml
+++ b/.github/workflows/ci-suse.yml
@@
 name: CI (openSUSE)
 on:
   push:
-    branches: [ "main" ]
+    branches: [ "master" ]
   pull_request:
   workflow_dispatch:
 permissions: { contents: read }
diff --git a/.github/workflows/ci-windows.yml b/.github/workflows/ci-windows.yml
--- a/.github/workflows/ci-windows.yml
+++ b/.github/workflows/ci-windows.yml
@@
 name: CI (Windows)
 on:
-  push:
-    branches: [ "main" ]
-  pull_request:
+  push:
+    branches: [ "master" ]
+  pull_request:
   workflow_dispatch:
 permissions: { contents: read }
diff --git a/.github/workflows/hex.yml b/.github/workflows/hex.yml
--- a/.github/workflows/hex.yml
+++ b/.github/workflows/hex.yml
@@
 name: BIN → HEX exporter
 
 on:
   push:
-    branches: [ "main" ]
+    branches: [ "master" ]
   pull_request:
   workflow_dispatch:
 
 permissions:
   contents: read
diff --git a/scripts/add_header_comment.sh b/scripts/add_header_comment.sh
new file mode 100755
--- /dev/null
+++ b/scripts/add_header_comment.sh
@@
+#!/usr/bin/env bash
+set -euo pipefail
+#
+# Adds a standard header comment to all scripts in ./scripts
+# Header:
+#   commit $long_id
+#   Author: Hans Kramer <kramer@b1-systems.de>
+#   Date:   <current date>
+#
+# - Inserts after a shebang if present, otherwise at file top.
+# - Skips files that already contain the Author line.
+# - Works for sh/bash/dash/ksh/py/ps1 and any text script.
+#
+
+ROOT="${1:-scripts}"
+LONG_ID="$(git rev-parse HEAD 2>/dev/null || echo "\$long_id")"
+DATE_STR="$(date -u +"%Y-%m-%d %H:%M:%SZ" || echo "DATE")"
+
+add_header() {
+  local f="$1"
+  # only text files
+  if file -b --mime "$f" 2>/dev/null | grep -q 'text/'; then
+    if grep -q 'Author: Hans Kramer <kramer@b1-systems.de>' "$f"; then
+      echo "skip (already has header): $f"
+      return 0
+    fi
+    tmp="$(mktemp)"
+    {
+      # read first line to check shebang
+      IFS= read -r first || true
+      if [[ "$first" =~ ^#! ]]; then
+        printf '%s\n' "$first"
+        printf '# commit %s\n' "$LONG_ID"
+        printf '# Author: Hans Kramer <kramer@b1-systems.de>\n'
+        printf '# Date:   %s\n' "$DATE_STR"
+        printf '\n'
+        # print rest
+        cat
+      else
+        printf '# commit %s\n' "$LONG_ID"
+        printf '# Author: Hans Kramer <kramer@b1-systems.de>\n'
+        printf '# Date:   %s\n' "$DATE_STR"
+        printf '\n'
+        printf '%s\n' "$first"
+        cat
+      fi
+    } < "$f" > "$tmp"
+    chmod --reference="$f" "$tmp" || true
+    mv "$tmp" "$f"
+    echo "header added: $f"
+  else
+    echo "skip (not text): $f"
+  fi
+}
+
+# default set: everything under scripts/
+mapfile -t FILES < <(git ls-files "$ROOT" 2>/dev/null || true)
+if [ "${#FILES[@]}" -eq 0 ]; then
+  # fallback: raw find (not just tracked files)
+  mapfile -t FILES < <(find "$ROOT" -type f)
+fi
+
+for f in "${FILES[@]}"; do
+  add_header "$f"
+done
+
+echo "Done."
PATCH
