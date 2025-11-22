DeepFace Minimal API (WSL2 / CPU)

Estrutura do projeto:
- requirements.txt
- app/
  - main.py
  - faces/  (armazenamento de imagens)
  - embeddings.json

Instruções:

1) Criar e ativar ambiente virtual (recomendado):
   python3 -m venv venv
   source venv/bin/activate   # no WSL2

2) Instalar dependências:
   pip install --upgrade pip
   pip install -r requirements.txt

3) Rodar API local:
   uvicorn app.main:app --host 0.0.0.0 --port 8000

4) Testar endpoints:
   - Cadastrar face:
     curl -X POST "http://localhost:8000/register/" -F "name=Paolo" -F "file=@/caminho/para/imagem.jpg"

   - Reconhecer face:
     curl -X POST "http://localhost:8000/recognize/" -F "file=@/caminho/para/imagem.jpg"

Notas:
- Compatível com WSL2 (CPU Intel/AMD)
- Usa TensorFlow CPU para evitar problemas de GPU
- Recomenda-se mapear pasta 'faces' para persistência, se desejar
