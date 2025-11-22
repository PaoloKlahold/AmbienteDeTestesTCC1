# face_recognition-wsl2

Projeto baseado na biblioteca `face_recognition` (dlib + HOG) para realizar cadastro e reconhecimento facial em ambiente WSL2.

## Funcionalidades
- Extração de embeddings com HOG ou CNN (dependendo da instalação do dlib)
- Armazenamento de vetores em `embeddings.json`
- Comparação euclidiana entre rostos cadastrados e imagens de teste

## Estrutura
- `app/main.py` — script principal
- `app/faces/` — banco local de imagens cadastradas
- `embeddings.json` — vetores faciais gerados

## Execução
Criar ambiente virtual:
```bash
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
