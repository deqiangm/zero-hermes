#!/bin/bash
# Initialize Database
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$PROJECT_ROOT/lib/common.sh"

echo "Initializing ZeroHermes V2 database..."
mkdir -p "$DATA_DIR"

for m in "$PROJECT_ROOT/etc/migrations"/*.sql; do
 [[ -f "$m" ]] && sql_exec "$(cat "$m")"
done

echo "Database: $DB_PATH"
echo "Version: $(get_schema_version)"
