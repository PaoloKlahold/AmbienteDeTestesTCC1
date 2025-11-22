#!/usr/bin/env python3
import json
import sys
import os
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment

if len(sys.argv) < 2:
    print("Uso: export_excel.py results.json")
    sys.exit(1)

path = sys.argv[1]

with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

# ---- AGRUPAR POR NOME ----
grouped = {}
for item in data:
    name = item["file"]

    if name not in grouped:
        grouped[name] = {}

    t = item["threshold"]

    resp = item.get("response")
    erro = item.get("erro")
    http = item.get("http_code")
    dist = None
    ident = None

    if isinstance(resp, dict):
        ident = resp.get("identity")
        dist = resp.get("distance")

    grouped[name][t] = {
        "identity": ident,
        "distance": dist,
        "elapsed": item.get("elapsed_ms"),
        "erro": erro,
        "http": http,
    }

# ---- thresholds fixos ----
THRESHOLDS = [0.3, 0.5, 0.7, 0.9, 1.1, 1.3]

# ---- CRIAR EXCEL ----
wb = Workbook()
ws = wb.active
ws.title = "Resultados"

# Cabeçalho
headers = ["Nome da Imagem"]
for t in THRESHOLDS:
    headers += [
        f"{t} Identity",
        f"{t} Distance",
        f"{t} Elapsed",
        f"{t} Erro"
    ]

ws.append(headers)

# Estilizar cabeçalho
for cell in ws[1]:
    cell.font = Font(bold=True)
    cell.alignment = Alignment(horizontal="center")

# Preencher linhas
for name, vals in grouped.items():
    row = [name]

    for t in THRESHOLDS:
        entry = vals.get(t, {})
        row.append(entry.get("identity"))
        row.append(entry.get("distance"))
        row.append(entry.get("elapsed"))
        row.append(entry.get("erro"))

    ws.append(row)

out_path = "results.xlsx"
if os.path.exists(out_path):
    os.remove(out_path)

wb.save(out_path)
print("Gerado results.xlsx")
