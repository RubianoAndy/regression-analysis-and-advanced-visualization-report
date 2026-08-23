from pathlib import Path

import numpy as np
import pandas as pd

PROJECT_ROOT = Path(__file__).resolve().parents[2]
DATA_DIR = PROJECT_ROOT / "data" / "dataset"
DATA_DIR.mkdir(parents=True, exist_ok=True)

rng = np.random.default_rng(42)
n = 120
sectores = rng.choice(
    ["Residencial", "Comercial", "Industrial"], size=n, p=[0.5, 0.3, 0.2]
)
base = {"Residencial": 250, "Comercial": 900, "Industrial": 2500}
amplitud = {"Residencial": 60, "Comercial": 220, "Industrial": 600}
tarifa = {"Residencial": 820, "Comercial": 710, "Industrial": 640}

consumo = np.array([rng.normal(base[s], amplitud[s]) for s in sectores]).clip(50)
costo = consumo * np.array([tarifa[s] for s in sectores]) * rng.normal(1, 0.04, n) / 1000

df = pd.DataFrame({
    "cliente_id": [f"CL-{i:03d}" for i in range(1, n + 1)],
    "sector": sectores,
    "consumo_kwh": consumo.round(1),
    "costo_miles_cop": costo.round(1),
})
df.to_csv(DATA_DIR / "consumo_energia.csv", index=False)

print(f"Dataset generado: {len(df)} clientes")
print(df.groupby("sector")[["consumo_kwh", "costo_miles_cop"]].mean().round(1))
print("\nOK - Fase 0: data/dataset/consumo_energia.csv")
