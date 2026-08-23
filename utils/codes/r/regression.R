library(ggplot2)

script_path <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0) {
    return(normalizePath(sub("^--file=", "", file_arg[1]), mustWork = FALSE))
  }
  for (i in seq_len(sys.nframe())) {
    ofile <- sys.frame(i)$ofile
    if (!is.null(ofile)) {
      return(normalizePath(ofile, mustWork = FALSE))
    }
  }
  if (requireNamespace("rstudioapi", quietly = TRUE) &&
      rstudioapi::isAvailable()) {
    contexto <- rstudioapi::getSourceEditorContext()
    if (!is.null(contexto) && nzchar(contexto$path)) {
      return(normalizePath(contexto$path, mustWork = FALSE))
    }
  }
  NULL
}

this_file <- script_path()
project_root <- if (is.null(this_file)) {
  normalizePath(getwd(), mustWork = FALSE)
} else {
  dirname(dirname(dirname(this_file)))
}

data_path <- file.path(project_root, "data", "dataset", "consumo_energia.csv")
processed_dir <- file.path(project_root, "data", "processed")
figures_dir <- file.path(project_root, "public", "assets", "images", "figures",
                         "r", "regression")

if (!file.exists(data_path)) {
  stop(sprintf(paste0("No se encontro el dataset en '%s'. Ejecuta el script ",
                      "desde este proyecto (Fase 1: dataset.py) antes de la ",
                      "verificacion cruzada."),
               data_path))
}

for (d in c(processed_dir, figures_dir)) {
  if (!dir.exists(d)) {
    dir.create(d, recursive = TRUE)
  }
}

cat(sprintf("Raiz del proyecto: %s\n", project_root))

sector_order <- c("Residencial", "Comercial", "Industrial")
sector_colors <- c(Residencial = "#a6bddb", Comercial = "#74a9cf",
                   Industrial = "#2b8cbe")
accent <- "#d95f02"

df <- read.csv(data_path)
df$sector <- factor(df$sector, levels = sector_order)
df$tarifa_cop_kwh <- df$costo_miles_cop * 1000 / df$consumo_kwh
n <- nrow(df)

m1 <- lm(costo_miles_cop ~ consumo_kwh, data = df)
m2 <- lm(costo_miles_cop ~ consumo_kwh + sector, data = df)
m3 <- lm(costo_miles_cop ~ consumo_kwh * sector, data = df)

cat("=== M1 - regresion lineal simple ===\n")
print(summary(m1))
cat("\n=== M3 - regresion multiple con interaccion ===\n")
print(summary(m3))

cat("\n=== Contraste F entre modelos anidados ===\n")
print(anova(m1, m2, m3))

rmse <- function(observado, predicho) sqrt(mean((observado - predicho)^2))

metricas <- data.frame(
  modelo = c("M1 - Simple", "M2 - Aditivo", "M3 - Interaccion"),
  r2 = round(c(summary(m1)$r.squared, summary(m2)$r.squared,
               summary(m3)$r.squared), 4),
  r2_ajustado = round(c(summary(m1)$adj.r.squared, summary(m2)$adj.r.squared,
                        summary(m3)$adj.r.squared), 4),
  aic = round(c(AIC(m1), AIC(m2), AIC(m3)), 1),
  rmse = round(c(rmse(df$costo_miles_cop, fitted(m1)),
                 rmse(df$costo_miles_cop, fitted(m2)),
                 rmse(df$costo_miles_cop, fitted(m3))), 2)
)
cat("\n=== Metricas de los tres modelos (R) ===\n")
print(metricas, row.names = FALSE)
cat("Nota: el AIC de R supera en 2,0 al de statsmodels porque R cuenta la\n",
    "varianza residual como un parametro mas. La diferencia es constante y\n",
    "no altera el orden de los modelos.\n")
write.csv(metricas, file.path(processed_dir, "comparacion_modelos_r.csv"),
          row.names = FALSE)

coef_m3 <- data.frame(
  termino = names(coef(m3)),
  coeficiente = round(unname(coef(m3)), 4),
  error_std = round(unname(summary(m3)$coefficients[, 2]), 4),
  estadistico_t = round(unname(summary(m3)$coefficients[, 3]), 2),
  p_valor = formatC(unname(summary(m3)$coefficients[, 4]), format = "e",
                    digits = 2),
  ic95_inferior = round(unname(confint(m3)[, 1]), 4),
  ic95_superior = round(unname(confint(m3)[, 2]), 4)
)
cat("\n=== Coeficientes de M3 en R ===\n")
print(coef_m3, row.names = FALSE)
write.csv(coef_m3, file.path(processed_dir, "regresion_multiple_r.csv"),
          row.names = FALSE)

orden_python <- c("(Intercept)", "sectorComercial", "sectorIndustrial",
                  "consumo_kwh", "consumo_kwh:sectorComercial",
                  "consumo_kwh:sectorIndustrial")
python_path <- file.path(processed_dir, "regresion_multiple.csv")
if (file.exists(python_path)) {
  coef_python <- read.csv(python_path)
  coef_r_ordenado <- coef(m3)[orden_python]
  comparacion <- data.frame(
    termino = coef_python$termino,
    termino_r = orden_python,
    python = coef_python$coeficiente,
    r = round(unname(coef_r_ordenado), 4),
    diferencia_absoluta = abs(coef_python$coeficiente -
                                round(unname(coef_r_ordenado), 4))
  )
  cat("\n=== Verificacion cruzada Python vs R (coeficientes de M3) ===\n")
  print(comparacion, row.names = FALSE)
  cat(sprintf("Diferencia maxima: %.10f\n",
              max(comparacion$diferencia_absoluta)))
  write.csv(comparacion, file.path(processed_dir, "verificacion_cruzada.csv"),
            row.names = FALSE)
} else {
  cat("\nNo se encontro regresion_multiple.csv: ejecuta antes la Fase 2.\n")
}

pendientes <- c(
  Residencial = unname(coef(m3)["consumo_kwh"]),
  Comercial = unname(coef(m3)["consumo_kwh"] +
                       coef(m3)["consumo_kwh:sectorComercial"]),
  Industrial = unname(coef(m3)["consumo_kwh"] +
                        coef(m3)["consumo_kwh:sectorIndustrial"])
)
cat("\n=== Tarifa implicita por sector (COP/kWh) ===\n")
print(round(pendientes * 1000, 1))

tema_informe <- theme_minimal(base_size = 11) +
  theme(plot.title = element_text(face = "bold"),
        panel.grid.minor = element_blank(),
        legend.position = "top")

g1 <- ggplot(df, aes(x = consumo_kwh, y = costo_miles_cop)) +
  geom_point(aes(color = sector), size = 2, alpha = 0.9) +
  geom_smooth(method = "lm", formula = y ~ x, color = accent,
              linewidth = 0.9, se = TRUE) +
  scale_color_manual(values = sector_colors, name = "Sector") +
  labs(title = "Regresión lineal simple del costo sobre el consumo (R)",
       subtitle = sprintf("R2 = %.4f, pendiente = %.1f COP/kWh",
                          summary(m1)$r.squared,
                          coef(m1)["consumo_kwh"] * 1000),
       x = "Consumo (kWh/mes)", y = "Costo facturado (miles de COP)") +
  tema_informe
ggsave(file.path(figures_dir, "ggplot_ajuste_simple.png"), g1,
       width = 7.2, height = 4.2, dpi = 150, type = "cairo")

etiquetas_tarifa <- setNames(
  sprintf("%s - %.0f COP/kWh", sector_order, pendientes[sector_order] * 1000),
  sector_order)
g2 <- ggplot(df, aes(x = consumo_kwh, y = costo_miles_cop, color = sector)) +
  geom_point(size = 2, alpha = 0.9) +
  geom_smooth(method = "lm", formula = y ~ x, se = TRUE, color = accent,
              linewidth = 0.9) +
  facet_wrap(~ sector, scales = "free",
             labeller = labeller(sector = etiquetas_tarifa)) +
  scale_color_manual(values = sector_colors, guide = "none") +
  labs(title = "Una regresión por sector: cada pendiente es una tarifa (R)",
       x = "Consumo (kWh/mes)", y = "Costo facturado (miles de COP)") +
  tema_informe
ggsave(file.path(figures_dir, "ggplot_ajuste_por_sector.png"), g2,
       width = 9.6, height = 3.8, dpi = 150, type = "cairo")

residuos <- rbind(
  data.frame(modelo = "M1 · simple", sector = df$sector,
             ajustado = fitted(m1), residuo = residuals(m1)),
  data.frame(modelo = "M3 · con interacción", sector = df$sector,
             ajustado = fitted(m3), residuo = residuals(m3))
)
g3 <- ggplot(residuos, aes(x = sector, y = residuo, fill = sector)) +
  geom_hline(yintercept = 0, color = accent, linewidth = 0.7) +
  geom_boxplot(alpha = 0.95, outlier.size = 1.2) +
  stat_summary(fun = mean, geom = "point", shape = 18, size = 3,
               color = accent) +
  facet_wrap(~ modelo) +
  scale_fill_manual(values = sector_colors, guide = "none") +
  labs(title = "El sesgo por sector desaparece al incluir la interacción (R)",
       subtitle = "El rombo marca el residuo medio de cada sector",
       x = "Sector", y = "Residuo (miles de COP)") +
  tema_informe
ggsave(file.path(figures_dir, "ggplot_residuos_por_sector.png"), g3,
       width = 9.0, height = 4.0, dpi = 150, type = "cairo")

png(file.path(figures_dir, "base_diagnostico_m1.png"),
    width = 2100, height = 1500, res = 200, type = "cairo")
par(mfrow = c(2, 2), mar = c(4, 4, 3, 1))
plot(m1, col = "#2c7fb8", pch = 19, cex = 0.6)
dev.off()

cat("\nOK - Fase 5: verificacion cruzada en R y figuras generadas\n")
