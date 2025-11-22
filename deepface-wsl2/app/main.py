from fastapi import FastAPI, UploadFile, File, HTTPException, Form, Query
from deepface import DeepFace
import os, shutil, json, numpy as np
import time

app = FastAPI(title="DeepFace Minimal API")

FACES_DIR = "faces"
EMBED_FILE = "embeddings.json"

os.makedirs(FACES_DIR, exist_ok=True)

if os.path.exists(EMBED_FILE):
    with open(EMBED_FILE, "r") as f:
        embeddings_db = json.load(f)
else:
    embeddings_db = {}

def save_embeddings():
    with open(EMBED_FILE, "w") as f:
        json.dump(embeddings_db, f)

def interpret_threshold(threshold: float):
    """
    Retorna título e descrição do nível de tolerância do threshold.
    """
    if threshold <= 0.3:
        return "EXTREMAMENTE RESTRITIVO", "quase nenhum rosto é aceito"
    elif threshold <= 0.5:
        return "MUITO RESTRITIVO", "apenas rostos quase idênticos são reconhecidos"
    elif threshold <= 0.7:
        return "RESTRITIVO", "pode falhar com pequenas variações de foto"
    elif threshold <= 0.9:
        return "MODERADO", "aceita pequenas diferenças de ângulo, iluminação ou qualidade"
    elif threshold <= 1.1:
        return "ABRANGENTE", "aceita variações significativas, mas ainda distingue pessoas diferentes"
    elif threshold <= 1.3:
        return "MUITO ABRANGENTE", "pode confundir rostos semelhantes"
    else:
        return "EXTREMAMENTE ABRANGENTE", "praticamente qualquer rosto é aceito"

@app.post('/register/')
async def register_face(name: str = Form(...), file: UploadFile = File(...)):
    filename = f"{name}__{file.filename}"
    file_path = os.path.join(FACES_DIR, filename)
    with open(file_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)

    try:
        rep = DeepFace.represent(img_path=file_path, model_name='ArcFace')
        if isinstance(rep, list) and len(rep)>0 and isinstance(rep[0], dict) and 'embedding' in rep[0]:
            embedding = rep[0]['embedding']
        elif isinstance(rep, dict) and 'embedding' in rep:
            embedding = rep['embedding']
        else:
            embedding = rep

        embeddings_db[name] = embedding
        save_embeddings()
        return {'message': f'Face de "{name}" cadastrada com sucesso.'}

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post('/recognize/')
async def recognize_face(
    file: UploadFile = File(...),
    threshold: float = Query(0.7, description="Distância máxima para considerar correspondência (quanto maior, mais permissivo)")
):
    filename = f"query__{file.filename}"
    file_path = os.path.join(FACES_DIR, filename)
    with open(file_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)

    if not embeddings_db:
        return {'identity': None, 'distance': None, 'message': 'Nenhuma face cadastrada.'}

    start_time = time.time()  # marca o início

    try:
        rep = DeepFace.represent(img_path=file_path, model_name='ArcFace')
        if isinstance(rep, list) and len(rep)>0 and isinstance(rep[0], dict) and 'embedding' in rep[0]:
            embedding = rep[0]['embedding']
        elif isinstance(rep, dict) and 'embedding' in rep:
            embedding = rep['embedding']
        else:
            embedding = rep

        min_dist = float('inf')
        identity = None
        for name, db_emb in embeddings_db.items():
            dist = np.linalg.norm(np.array(db_emb) - np.array(embedding))
            if dist < min_dist:
                min_dist = float(dist)
                identity = name

        threshold_title, threshold_description = interpret_threshold(threshold)
        end_time = time.time()  # marca o fim
        elapsed_ms = (end_time - start_time) * 1000  # em milissegundos

        if identity and min_dist < threshold:
            return {
                'identity': identity,
                'distance': min_dist,
                'threshold': threshold,
                'threshold_title': threshold_title,
                'threshold_description': threshold_description,
                'elapsed_ms': elapsed_ms
            }
        else:
            return {
                'identity': None,
                'distance': min_dist,
                'threshold': threshold,
                'threshold_title': threshold_title,
                'threshold_description': threshold_description,
                'elapsed_ms': elapsed_ms
            }

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
