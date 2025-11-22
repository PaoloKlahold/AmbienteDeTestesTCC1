# deepface_cli

Ferramenta em linha de comando para cadastro e reconhecimento facial utilizando a biblioteca DeepFace.

## Funcionalidades
- Cadastro automático de rostos a partir da pasta `FotosCadastro/`
- Testes de reconhecimento usando imagens em `FotosTeste/`
- Scripts auxiliares para automação (register_all.sh e test_all.sh)
- Exportação de resultados para Excel

## Estrutura
- `FotosCadastro/` — imagens para cadastro
- `FotosTeste/` — imagens para teste
- `scripts/` — automações e utilidades

## Execução
Crie o ambiente virtual:
```bash
python -m venv venv_cli
source venv_cli/bin/activate
pip install -r requirements.txt
