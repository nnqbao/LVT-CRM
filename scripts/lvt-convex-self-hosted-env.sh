#!/bin/zsh
set -euo pipefail

if (( $# == 0 )); then
  echo "usage: $0 <command> [args...]" >&2
  exit 64
fi

# This checkout's reservation (untracked infra/convex-local/.env, never a tracked literal).
backend_port="$(sed -n 's/^LVT_CONVEX_BACKEND_PORT=\([0-9][0-9]*\)$/\1/p' "${0:A:h:h}/infra/convex-local/.env" 2>/dev/null)"
if [[ -z "$backend_port" ]]; then
  echo "no LVT_CONVEX_BACKEND_PORT in infra/convex-local/.env (copy .env.example)" >&2
  exit 78
fi
export CONVEX_SELF_HOSTED_URL="http://127.0.0.1:${backend_port}"
if ! admin_key="$(
  security find-generic-password \
    -s lvt-convex-local-admin-key \
    -a lvt-crm \
    -w
)"; then
  echo "failed to read lvt-convex-local-admin-key from Keychain" >&2
  exit 78
fi
if [[ -z "$admin_key" ]]; then
  echo "lvt-convex-local-admin-key is empty" >&2
  exit 78
fi
export CONVEX_SELF_HOSTED_ADMIN_KEY="$admin_key"
export CONVEX_DEPLOYMENT=""

exec "$@"
