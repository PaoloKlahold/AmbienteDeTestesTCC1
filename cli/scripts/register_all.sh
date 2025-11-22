#!/bin/bash
API_URL="http://localhost:8000/register/"
DIR="FotosCadastro"

for f in "$DIR"/*; do
  [ -f "$f" ] || continue
  name=$(basename "$f")
  name="${name%.*}"
  curl -s -X POST "$API_URL" -F "name=$name" -F "file=@$f"
  echo
done
