from pathlib import Path

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from sklearn.compose import ColumnTransformer
from sklearn.linear_model import LinearRegression
from sklearn.metrics import (mean_absolute_error,
                             mean_absolute_percentage_error,
                             mean_squared_error, r2_score)
from sklearn.model_selection import (KFold, cross_validate, train_test_split)
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import (OneHotEncoder, PolynomialFeatures,
                                   StandardScaler)

PROJECT_ROOT = Path(__file__).resolve().parents[2]
DATA_DIR = PROJECT_ROOT / "data" / "dataset"
PROCESSED_DIR = PROJECT_ROOT / "data" / "processed"
FIGURES_DIR = (
    PROJECT_ROOT / "public" / "assets" / "images" / "figures" / "python" / "regression"
)
for d in (PROCESSED_DIR, FIGURES_DIR):
    d.mkdir(parents=True, exist_ok=True)

plt.rcParams.update({
    "figure.dpi": 150, "font.size": 10, "axes.titlesize": 11,
    "axes.titleweight": "bold", "axes.grid": True, "grid.alpha": 0.3,
    "axes.axisbelow": True,
})

SEMILLA = 42
SECTOR_ORDER = ["Residencial", "Comercial", "Industrial"]
SECTOR_COLORS = {"Residencial": "#a6bddb", "Comercial": "#74a9cf",
                 "Industrial": "#2b8cbe"}
ACCENT = "#d95f02"

df = pd.read_csv(DATA_DIR / "consumo_energia.csv")
X = df[["consumo_kwh", "sector"]]
y = df["costo_miles_cop"]

X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.30, random_state=SEMILLA, stratify=df["sector"])
print(f"Entrenamiento: {len(X_train)} clientes | Prueba: {len(X_test)} clientes")
print(pd.concat([
    X_train["sector"].value_counts().rename("entrenamiento"),
    X_test["sector"].value_counts().rename("prueba"),
], axis=1).loc[SECTOR_ORDER].to_string())

pipe_simple = Pipeline([
    ("preprocesamiento", ColumnTransformer([
        ("numerica", StandardScaler(), ["consumo_kwh"]),
    ])),
    ("estimador", LinearRegression()),
])

pipe_multiple = Pipeline([
    ("preprocesamiento", ColumnTransformer([
        ("numerica", StandardScaler(), ["consumo_kwh"]),
        ("categorica", OneHotEncoder(drop="first", sparse_output=False),
         ["sector"]),
    ])),
    ("interaccion", PolynomialFeatures(degree=2, interaction_only=True,
                                       include_bias=False)),
    ("estimador", LinearRegression()),
])

modelos = {
    "MCO simple (solo consumo)": pipe_simple,
    "MCO múltiple (consumo × sector)": pipe_multiple,
}

cv = KFold(n_splits=10, shuffle=True, random_state=SEMILLA)
filas, predicciones = [], {}
for nombre, pipe in modelos.items():
    pipe.fit(X_train, y_train)
    pred_test = pipe.predict(X_test)
    predicciones[nombre] = pred_test
    marcador = cross_validate(pipe, X, y, cv=cv,
                              scoring=["r2", "neg_root_mean_squared_error"])
    filas.append({
        "modelo": nombre,
        "r2_entrenamiento": round(r2_score(y_train, pipe.predict(X_train)), 4),
        "r2_prueba": round(r2_score(y_test, pred_test), 4),
        "rmse_prueba": round(float(np.sqrt(mean_squared_error(y_test, pred_test))), 2),
        "mae_prueba": round(mean_absolute_error(y_test, pred_test), 2),
        "mape_prueba_pct": round(
            mean_absolute_percentage_error(y_test, pred_test) * 100, 2),
        "r2_cv_media": round(marcador["test_r2"].mean(), 4),
        "rmse_cv_media": round(
            -marcador["test_neg_root_mean_squared_error"].mean(), 2),
        "rmse_cv_desv": round(
            marcador["test_neg_root_mean_squared_error"].std(), 2),
    })

metricas = pd.DataFrame(filas)
metricas.to_csv(PROCESSED_DIR / "sklearn_metricas.csv", index=False)
print("\nDesempeño de las dos especificaciones")
print(metricas.to_string(index=False))

mejor = metricas.loc[metricas["rmse_cv_media"].idxmin(), "modelo"]
mejora = (1 - metricas.loc[metricas["modelo"] == mejor, "rmse_cv_media"].iloc[0]
          / metricas["rmse_cv_media"].max()) * 100
print(f"\nMenor RMSE en validación cruzada: {mejor}")
print(f"Reducción del error frente a la especificación simple: {mejora:.1f} %")

pred_mejor = predicciones[mejor]
sector_test = df.loc[X_test.index, "sector"]
residuo_test = y_test - pred_mejor

fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(10.6, 4.0))
for s in SECTOR_ORDER:
    m = (sector_test == s).to_numpy()
    ax1.scatter(pred_mejor[m], y_test[m], s=34, color=SECTOR_COLORS[s],
                edgecolor="white", linewidth=0.5, label=s)
limite = [0, float(y_test.max()) * 1.08]
ax1.plot(limite, limite, color=ACCENT, lw=1.4, linestyle="--",
         label="Predicción perfecta")
fila = metricas[metricas["modelo"] == mejor].iloc[0]
ax1.set_title(f"Prueba retenida: R² = {fila['r2_prueba']:.4f}, "
              f"RMSE = {fila['rmse_prueba']:,.1f}")
ax1.set_xlabel("Costo predicho (miles de COP)")
ax1.set_ylabel("Costo observado (miles de COP)")
ax1.legend(fontsize=8, loc="upper left")

for s in SECTOR_ORDER:
    m = (sector_test == s).to_numpy()
    ax2.scatter(pred_mejor[m], residuo_test[m], s=34, color=SECTOR_COLORS[s],
                edgecolor="white", linewidth=0.5, label=s)
ax2.axhline(0, color=ACCENT, lw=1.2)
ax2.set_title("Residuos de prueba: sin sesgo visible por sector")
ax2.set_xlabel("Costo predicho (miles de COP)")
ax2.set_ylabel("Residuo (miles de COP)")
ax2.legend(fontsize=8, loc="lower left")
fig.suptitle(f"Validación del modelo seleccionado · {mejor}",
             fontsize=12, fontweight="bold")
fig.tight_layout()
fig.savefig(FIGURES_DIR / "real_vs_predicho.png")
plt.close(fig)

print("\nOK - Fase 3: validación con scikit-learn y figura generadas")
