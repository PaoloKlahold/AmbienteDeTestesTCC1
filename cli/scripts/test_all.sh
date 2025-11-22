#!/usr/bin/env bash
set -o pipefail

API_URL="http://localhost:8000/recognize/"
TEST_DIR="FotosTeste"
OUT="results.json"

THRESHOLDS=(0.3 0.5 0.7 0.9 1.1 1.3)
TIMEOUT_SECONDS=8
SAFETY_DELAY_OK=0.2
SAFETY_DELAY_ERR=4.0

command -v python3 >/dev/null 2>&1 || { echo "python3 não encontrado"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "curl não encontrado"; exit 1; }

# cria results.json vazio se não existir
printf "[]" > "$OUT"

total_photos=$(find "$TEST_DIR" -maxdepth 1 -type f | wc -l)
if [ "$total_photos" -eq 0 ]; then
  echo "Nenhuma foto encontrada em $TEST_DIR"
  exit 1
fi

photo_index=0

print_status() {
  local photo="$1"
  local threshold="$2"
  local index="$3"
  local total="$4"
  local elapsed="$5"
  printf "\rProcessando: %s | Threshold: %s | %d/%d | %4.1fs\033[K" \
         "$photo" "$threshold" "$index" "$total" "$elapsed"
}

# append robusto via Python (agora aceita campo erro opcional)
append_result() {
  local file_name="$1"
  local threshold_val="$2"
  local elapsed_ms="$3"
  local http_code="$4"
  local curl_rc="$5"
  local tmp_body_path="$6"
  local tmp_err_path="$7"
  local erro_label="$8" # pode ser vazio

python3 - <<PY
import json,os
out_path = "$OUT"
file_name = "$file_name"
threshold = float("$threshold_val")
elapsed_ms = int("$elapsed_ms")
http_code = "$http_code"
curl_rc = int("$curl_rc")
tmp_body = "$tmp_body_path"
tmp_err = "$tmp_err_path"
erro_label = "$erro_label" if "$erro_label" != "" else None

# read existing results
try:
    with open(out_path, "r", encoding="utf-8") as f:
        arr = json.load(f)
except Exception:
    arr = []

# read body
try:
    with open(tmp_body, "r", encoding="utf-8", errors="replace") as f:
        body_text = f.read()
except Exception:
    body_text = ""

# attempt parse body as json
resp = None
try:
    if body_text:
        resp = json.loads(body_text)
    else:
        resp = None
except Exception:
    resp = body_text

# read curl stderr
try:
    with open(tmp_err, "r", encoding="utf-8", errors="replace") as f:
        curl_err_text = f.read()
except Exception:
    curl_err_text = ""

entry = {
    "file": file_name,
    "threshold": threshold,
    "elapsed_ms": elapsed_ms,
    "http_code": http_code,
    "curl_rc": curl_rc,
    "response": resp,
    "curl_err": curl_err_text
}
if erro_label:
    entry["erro"] = erro_label

arr.append(entry)

# write back atomically
tmp_out = out_path + ".tmp"
with open(tmp_out, "w", encoding="utf-8") as f:
    json.dump(arr, f, ensure_ascii=False, indent=2)
os.replace(tmp_out, out_path)
PY
}

# phrase from API that indicates face couldn't be detected
FACE_NOT_DETECTED_PHRASE="Please confirm that the picture is a face photo or consider to set enforce_detection param to False"
FACE_NOT_DETECTED_PHRASE_2="Nenhuma face detectada na imagem"

for file in "$TEST_DIR"/*; do
  [ -f "$file" ] || continue
  filename=$(basename -- "$file")
  ((photo_index++))

  abort_image=false

  for t in "${THRESHOLDS[@]}"; do
    if [ "$abort_image" = true ]; then
        break
    fi

    start_ns=$(date +%s%N 2>/dev/null || echo 0)
    start_ms=$(( start_ns / 1000000 ))

    print_status "$filename" "$t" "$photo_index" "$total_photos" 0.0

    tmp_body=$(mktemp)
    tmp_err=$(mktemp)

    http_code=$(curl -sS --max-time "$TIMEOUT_SECONDS" \
                 -w "%{http_code}" \
                 -o "$tmp_body" \
                 -X POST "${API_URL}?threshold=${t}" \
                 -F "file=@${file}" 2> "$tmp_err")
    curl_rc=$?

    end_ns=$(date +%s%N 2>/dev/null || echo 0)
    end_ms=$(( end_ns / 1000000 ))
    elapsed_ms=$(( end_ms - start_ms ))
    if [ "$elapsed_ms" -lt 0 ]; then elapsed_ms=0; fi
    elapsed_s=$(awk -v ms="$elapsed_ms" 'BEGIN{printf "%.1f", ms/1000}')

    print_status "$filename" "$t" "$photo_index" "$total_photos" "$elapsed_s"

    # read body early for inspection
    body_raw=$(cat "$tmp_body" 2>/dev/null || echo "")

    # handle curl timeout
    if [ "$curl_rc" -eq 28 ]; then
      echo -e "\n[ERRO TIMEOUT] $filename | Threshold $t"
      append_result "$filename" "$t" "$elapsed_ms" "000" "$curl_rc" "$tmp_body" "$tmp_err" ""
      abort_image=true
      sleep "$SAFETY_DELAY_ERR"
      rm -f "$tmp_body" "$tmp_err"
      continue
    fi

    # handle curl failure
    if [ "$curl_rc" -ne 0 ]; then
      curl_err_text=$(cat "$tmp_err" 2>/dev/null || echo "")
      echo -e "\n[ERRO CURL] $filename | Threshold $t → ${curl_err_text:-(no msg)}"
      append_result "$filename" "$t" "$elapsed_ms" "000" "$curl_rc" "$tmp_body" "$tmp_err" ""
      abort_image=true
      sleep "$SAFETY_DELAY_ERR"
      rm -f "$tmp_body" "$tmp_err"
      continue
    fi

    if [ -z "$http_code" ]; then http_code="000"; fi

    # If HTTP != 200, check if API returned the face-not-detected message.
    if [ "$http_code" != "200" ]; then
      if echo "$body_raw" | grep -F "$FACE_NOT_DETECTED_PHRASE" >/dev/null 2>&1 \
        || echo "$body_raw" | grep -F "$FACE_NOT_DETECTED_PHRASE_2" >/dev/null 2>&1; then

        # treat as non-fatal: record entry with erro label and continue with thresholds
        echo -e "\n[ROSTO NÃO IDENTIFICADO] $filename | Threshold $t"
        append_result "$filename" "$t" "$elapsed_ms" "$http_code" "$curl_rc" "$tmp_body" "$tmp_err" "Rosto não identificado"
        # small safety pause, but do NOT abort the image
        sleep "$SAFETY_DELAY_OK"
        rm -f "$tmp_body" "$tmp_err"
        continue
      else
        # real server error - abort thresholds for this image
        snippet=$(head -c 400 "$tmp_body" 2>/dev/null || echo "")
        echo -e "\n[ERRO API] $filename | Threshold $t → HTTP $http_code | ${snippet:-(no body)}"
        append_result "$filename" "$t" "$elapsed_ms" "$http_code" "$curl_rc" "$tmp_body" "$tmp_err" ""
        abort_image=true
        sleep "$SAFETY_DELAY_ERR"
        rm -f "$tmp_body" "$tmp_err"
        continue
      fi
    fi

    # success (200) - append result normally
    append_result "$filename" "$t" "$elapsed_ms" "$http_code" "$curl_rc" "$tmp_body" "$tmp_err" ""

    sleep "$SAFETY_DELAY_OK"
    rm -f "$tmp_body" "$tmp_err"
  done
done

echo
echo "Finalizado. Arquivo: $OUT"
echo "Opções: 1) Imprimir tabela  2) Exportar Excel"
read -p "Escolha: " opt
if [ "$opt" = "1" ]; then
  python3 - <<'PY'
import json,sys
with open("results.json","r",encoding="utf-8") as f:
    print(json.dumps(json.load(f), ensure_ascii=False, indent=2))
PY
elif [ "$opt" = "2" ]; then
  python3 scripts/export_excel.py "results.json"
  echo "Gerado results.xlsx"
else
  echo "Opção inválida."
fi
