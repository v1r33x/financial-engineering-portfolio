############################################################
# STOCHASTIC MORTALITY MODELLING & LIFE INSURER ALM
# Countries  : Belgium, UK, Netherlands
# Models     : Lee-Carter + Cairns-Blake-Dowd (CBD)
# Application: Life insurer solvency under Solvency II stress
############################################################

############################################################
# 0. LIBRARIES
############################################################
library(tidyverse)      # data manipulation and plotting
library(ggplot2)        # plots
library(scales)         # axis formatting

############################################################
# 1. LOAD MORTALITY DATA FROM LOCAL FILES
############################################################
# HMD files were downloaded manually from mortality.org
# Mx_1x1 = death rates by single year of age and single calendar year

data_path <- "C:/Masters of Actuarial and Financial Engineering/Projects/detailedproject/insurance-ALM/"

read_hmd_mx <- function(filepath) {
  # HMD files have 2 header lines — skip them
  # Columns: Year, Age, Female, Male, Total
  raw <- read.table(filepath, header = TRUE, skip = 2,
                    na.strings = ".", stringsAsFactors = FALSE)
  # Age column may contain "110+" — convert to numeric, dropping the +
  raw$Age <- as.numeric(gsub("\\+", "", raw$Age))
  return(raw)
}

bel <- read_hmd_mx(paste0(data_path, "Mx_1x1_bel.txt"))
uk  <- read_hmd_mx(paste0(data_path, "Mx_1x1_uk.txt"))
nld <- read_hmd_mx(paste0(data_path, "Mx_1x1_neth.txt"))

mort_data <- list(Belgium = bel, UK = uk, Netherlands = nld)

cat("Belgium rows:", nrow(bel), "\n")
cat("UK rows:",      nrow(uk),  "\n")
cat("NLD rows:",     nrow(nld), "\n")

############################################################
# 2. PREPARE DATA — FILTER AGES AND YEARS
############################################################
# Focus on ages 50-90 and years 1970-2020.
# Ages below 50 are less relevant for life insurance liability modelling.
# Log death rates are used because they are more symmetric and
# better behaved statistically than raw rates.

AGE_MIN  <- 50
AGE_MAX  <- 90
YEAR_MIN <- 1970
YEAR_MAX <- 2020

prep_mx <- function(data, age_min, age_max, year_min, year_max) {
  if (is.null(data)) return(NULL)
  
  d <- data %>%
    filter(Age >= age_min, Age <= age_max,
           Year >= year_min, Year <= year_max) %>%
    select(Year, Age, Total)
  
  if (nrow(d) == 0) return(NULL)
  
  # Pivot to matrix: rows = ages, columns = years
  mx_mat <- d %>%
    pivot_wider(names_from = Year, values_from = Total) %>%
    arrange(Age) %>%
    select(-Age) %>%
    as.matrix()
  
  rownames(mx_mat) <- age_min:age_max
  
  # Replace zeros/NAs before log transform
  mx_mat[!is.finite(mx_mat) | mx_mat <= 0] <- 1e-6
  
  return(log(mx_mat))
}

log_mx <- lapply(mort_data, prep_mx,
                 age_min = AGE_MIN, age_max = AGE_MAX,
                 year_min = YEAR_MIN, year_max = YEAR_MAX)
names(log_mx) <- c("Belgium", "UK", "Netherlands")

cat("Belgium matrix dim:", dim(log_mx[["Belgium"]]), "\n")
cat("UK matrix dim:",      dim(log_mx[["UK"]]),      "\n")
cat("NLD matrix dim:",     dim(log_mx[["Netherlands"]]), "\n")

country_names <- c("Belgium", "UK", "Netherlands")

############################################################
# 3. LEE-CARTER MODEL
############################################################
# The Lee-Carter model decomposes log mortality as:
# log(mx[x,t]) = ax + bx * kt + error
#
# ax = average log death rate at age x (fixed age pattern)
# bx = sensitivity of age x to the time index
# kt = time index (captures overall mortality improvement over time)
#
# Fitting method: Singular Value Decomposition (SVD).
# SVD factorises the demeaned log-mortality matrix into its
# best rank-1 approximation — the most efficient two-component summary.

fit_lee_carter <- function(log_mx_mat) {
  
  ages  <- as.numeric(rownames(log_mx_mat))
  years <- as.numeric(colnames(log_mx_mat))
  
  # Step 1: ax = row mean (average log rate at each age)
  ax <- rowMeans(log_mx_mat)
  
  # Step 2: subtract ax to isolate the time-varying part
  centered <- log_mx_mat - ax
  
  # Step 3: SVD — rank-1 factorisation
  svd_fit <- svd(centered, nu = 1, nv = 1)
  
  bx <- svd_fit$u[, 1]
  kt <- svd_fit$d[1] * svd_fit$v[, 1]
  
  # Step 4: normalise so sum(bx) = 1
  bx_sum <- sum(bx)
  bx <- bx / bx_sum
  kt <- kt * bx_sum
  
  # Step 5: drift = average annual change in kt
  drift <- mean(diff(kt))
  
  names(ax) <- ages
  names(bx) <- ages
  names(kt) <- years
  
  return(list(ax = ax, bx = bx, kt = kt, drift = drift,
              ages = ages, years = years, log_mx = log_mx_mat))
}

lc_fits <- lapply(log_mx, function(m) {
  if (is.null(m)) return(NULL)
  fit_lee_carter(m)
})
names(lc_fits) <- country_names

cat("Lee-Carter fitted for all countries.\n")

############################################################
# 4. CBD MODEL
############################################################
# The Cairns-Blake-Dowd model (2006) is designed for ages 50+.
# It models the logit of death probability:
# logit(qx[x,t]) = k1t + k2t * (x - xbar)
#
# k1t = time-varying intercept (overall mortality level)
# k2t = time-varying slope (how mortality changes across ages)
# xbar = mean age (centres the age variable for numerical stability)
#
# Fitted by OLS regression at each year separately.
# qx = 1 - exp(-mx) converts death rates to probabilities.

fit_cbd <- function(log_mx_mat) {
  
  ages  <- as.numeric(rownames(log_mx_mat))
  years <- as.numeric(colnames(log_mx_mat))
  xbar  <- mean(ages)
  
  mx_mat   <- exp(log_mx_mat)
  qx_mat   <- 1 - exp(-mx_mat)
  qx_mat   <- pmin(pmax(qx_mat, 1e-6), 1 - 1e-6)
  logit_qx <- log(qx_mat / (1 - qx_mat))
  
  k1 <- rep(NA, length(years))
  k2 <- rep(NA, length(years))
  
  for (j in seq_along(years)) {
    y   <- logit_qx[, j]
    x_c <- ages - xbar
    fit <- lm(y ~ x_c)
    k1[j] <- coef(fit)[1]
    k2[j] <- coef(fit)[2]
  }
  
  names(k1) <- years
  names(k2) <- years
  
  drift1 <- mean(diff(k1))
  drift2 <- mean(diff(k2))
  
  return(list(k1 = k1, k2 = k2,
              drift1 = drift1, drift2 = drift2,
              xbar = xbar, ages = ages, years = years,
              logit_qx = logit_qx))
}

cbd_fits <- lapply(log_mx, function(m) {
  if (is.null(m)) return(NULL)
  fit_cbd(m)
})
names(cbd_fits) <- country_names

cat("CBD fitted for all countries.\n")

############################################################
# 5. MODEL COMPARISON — FITTING ERROR AND AIC
############################################################
# RMSE = Root Mean Squared Error — average prediction error (lower = better)
# AIC  = Akaike Information Criterion — penalises complexity (lower = better)

compute_lc_rmse <- function(lc) {
  fitted <- outer(lc$bx, lc$kt) + lc$ax
  resid  <- lc$log_mx - fitted
  sqrt(mean(resid^2))
}

compute_cbd_rmse <- function(cbd) {
  ages  <- cbd$ages
  xbar  <- cbd$xbar
  fitted_logit <- outer(rep(1, length(ages)), cbd$k1) +
    outer(ages - xbar, cbd$k2)
  resid <- cbd$logit_qx - fitted_logit
  sqrt(mean(resid^2))
}

n_ages  <- AGE_MAX - AGE_MIN + 1
n_years <- YEAR_MAX - YEAR_MIN + 1

lc_n_params  <- 2 * n_ages + n_years - 2
cbd_n_params <- 2 * n_years

comparison_df <- data.frame()

for (cn in country_names) {
  if (is.null(lc_fits[[cn]]) || is.null(cbd_fits[[cn]])) next
  
  lc_rmse  <- compute_lc_rmse(lc_fits[[cn]])
  cbd_rmse <- compute_cbd_rmse(cbd_fits[[cn]])
  
  n_obs   <- n_ages * n_years
  lc_aic  <- n_obs * log(lc_rmse^2)  + 2 * lc_n_params
  cbd_aic <- n_obs * log(cbd_rmse^2) + 2 * cbd_n_params
  
  comparison_df <- rbind(comparison_df, data.frame(
    Country    = cn,
    LC_RMSE    = round(lc_rmse,  5),
    CBD_RMSE   = round(cbd_rmse, 5),
    LC_AIC     = round(lc_aic,   1),
    CBD_AIC    = round(cbd_aic,  1),
    Better_Fit = ifelse(lc_rmse < cbd_rmse, "Lee-Carter", "CBD")
  ))
}

cat("\n--- Model Comparison: Lee-Carter vs CBD ---\n")
print(comparison_df, row.names = FALSE)

############################################################
# 6. MORTALITY PROJECTIONS WITH UNCERTAINTY
############################################################
# Project 30 years forward by simulating future kt (LC) and
# k1t, k2t (CBD) as random walks with drift.
# Random walk with drift: next = current + drift + Normal(0, sigma)
# sigma = std dev of historical annual changes in the index
# 1000 simulations give a distribution of future outcomes.

N_SIM  <- 1000
N_PROJ <- 30

project_lc <- function(lc, n_sim, n_proj) {
  
  kt_last <- tail(lc$kt, 1)
  drift   <- lc$drift
  sigma   <- sd(diff(lc$kt))
  
  kt_sim <- matrix(NA, nrow = n_proj, ncol = n_sim)
  
  for (s in 1:n_sim) {
    kt_path <- numeric(n_proj)
    kt_prev <- kt_last
    for (t in 1:n_proj) {
      kt_path[t] <- kt_prev + drift + rnorm(1, 0, sigma)
      kt_prev    <- kt_path[t]
    }
    kt_sim[, s] <- kt_path
  }
  
  proj_years <- max(lc$years) + 1:n_proj
  kt_central <- kt_last + drift * 1:n_proj
  mx_central <- exp(outer(lc$bx, kt_central) + lc$ax)
  
  mx_sims <- array(NA, dim = c(length(lc$ages), n_proj, n_sim))
  for (s in 1:n_sim) {
    mx_sims[,,s] <- exp(outer(lc$bx, kt_sim[,s]) + lc$ax)
  }
  
  mx_lower <- apply(mx_sims, c(1,2), quantile, 0.05)
  mx_upper <- apply(mx_sims, c(1,2), quantile, 0.95)
  
  list(years = proj_years, central = mx_central,
       lower = mx_lower, upper = mx_upper, sims = mx_sims)
}

project_cbd <- function(cbd, n_sim, n_proj) {
  
  k1_last <- tail(cbd$k1, 1)
  k2_last <- tail(cbd$k2, 1)
  sigma1  <- sd(diff(cbd$k1))
  sigma2  <- sd(diff(cbd$k2))
  
  proj_years <- max(cbd$years) + 1:n_proj
  ages  <- cbd$ages
  xbar  <- cbd$xbar
  
  k1_central <- k1_last + cbd$drift1 * 1:n_proj
  k2_central <- k2_last + cbd$drift2 * 1:n_proj
  
  logit_central <- outer(rep(1, length(ages)), k1_central) +
    outer(ages - xbar, k2_central)
  qx_central <- exp(logit_central) / (1 + exp(logit_central))
  mx_central <- -log(1 - qx_central)
  
  mx_sims <- array(NA, dim = c(length(ages), n_proj, n_sim))
  
  for (s in 1:n_sim) {
    k1_path <- numeric(n_proj)
    k2_path <- numeric(n_proj)
    k1_prev <- k1_last
    k2_prev <- k2_last
    
    for (t in 1:n_proj) {
      k1_path[t] <- k1_prev + cbd$drift1 + rnorm(1, 0, sigma1)
      k2_path[t] <- k2_prev + cbd$drift2 + rnorm(1, 0, sigma2)
      k1_prev    <- k1_path[t]
      k2_prev    <- k2_path[t]
    }
    
    logit_s      <- outer(rep(1, length(ages)), k1_path) +
      outer(ages - xbar, k2_path)
    qx_s         <- exp(logit_s) / (1 + exp(logit_s))
    mx_sims[,,s] <- -log(1 - qx_s)
  }
  
  mx_lower <- apply(mx_sims, c(1,2), quantile, 0.05)
  mx_upper <- apply(mx_sims, c(1,2), quantile, 0.95)
  
  list(years = proj_years, central = mx_central,
       lower = mx_lower, upper = mx_upper, sims = mx_sims)
}

cat("\nRunning projections (this takes a minute)...\n")
lc_proj  <- lapply(lc_fits,  function(f) if (!is.null(f)) project_lc(f,  N_SIM, N_PROJ))
cbd_proj <- lapply(cbd_fits, function(f) if (!is.null(f)) project_cbd(f, N_SIM, N_PROJ))
names(lc_proj)  <- country_names
names(cbd_proj) <- country_names
cat("Done.\n")

############################################################
# 7. LIFE INSURER PORTFOLIO
############################################################
# Stylized whole-life insurer:
# 1000 policyholders aged 50-80, EUR 100k death benefit each.
# Liability = present value of all future expected death payments.
# PV = sum over t of: surv_prob * qx_t * benefit / (1+r)^t
# surv_prob = probability of surviving to year t (updated each year)
# qx_t = probability of dying in year t given survival to t

BENEFIT    <- 100000
AGES_PORT  <- 50:80
R_BASE     <- 0.03
MAX_AGE    <- 110
base_country <- "Belgium"

compute_liability <- function(lc_fit, lc_projection, r, benefit, ages_port) {
  
  hist_ages <- lc_fit$ages
  proj_mx   <- lc_projection$central
  
  total_liability <- 0
  
  for (entry_age in ages_port) {
    
    surv_prob <- 1.0
    pv        <- 0.0
    
    for (t in 1:N_PROJ) {
      
      current_age <- entry_age + t - 1
      if (current_age > MAX_AGE) break
      if (current_age > max(hist_ages)) break
      
      age_idx <- which(hist_ages == min(current_age, max(hist_ages)))
      if (length(age_idx) == 0) next
      
      if (t <= ncol(proj_mx)) {
        mx_t <- proj_mx[age_idx, t]
      } else {
        mx_t <- proj_mx[age_idx, ncol(proj_mx)]
      }
      
      qx_t     <- 1 - exp(-mx_t)
      discount <- 1 / (1 + r)^t
      pv       <- pv + surv_prob * qx_t * benefit * discount
      
      surv_prob <- surv_prob * (1 - qx_t)
    }
    
    total_liability <- total_liability + pv
  }
  
  return(total_liability)
}

cat("\nComputing base liabilities...\n")

L_base <- compute_liability(
  lc_fits[[base_country]],
  lc_proj[[base_country]],
  r         = R_BASE,
  benefit   = BENEFIT,
  ages_port = AGES_PORT
)

# Assets funded at 105% of base liability (5% solvency buffer)
ASSETS <- L_base * 1.05

cat("Base Liability (EUR):", format(round(L_base), big.mark = ","), "\n")
cat("Assets (EUR)        :", format(round(ASSETS),  big.mark = ","), "\n")
cat("Base Solvency Ratio :", round(ASSETS / L_base * 100, 1), "%\n")

############################################################
# 8. SOLVENCY II STRESS TESTING
############################################################
# Solvency II requires capital sufficient to survive a 1-in-200 year event.
# Mortality stress: +15% death rates (people die faster than projected)
# Interest rate stress: -1% discount rate (raises PV of liabilities)
# Combined: both simultaneously (realistic worst case)
# Solvency ratio = Assets / Liabilities * 100%
# Below 100% = regulatory insolvency

lc_proj_stress         <- lc_proj[[base_country]]
lc_proj_stress$central <- lc_proj_stress$central * 1.15

L_mort_stress <- compute_liability(
  lc_fits[[base_country]], lc_proj_stress,
  r = R_BASE, benefit = BENEFIT, ages_port = AGES_PORT
)

R_STRESS <- max(R_BASE - 0.01, 0.005)

L_rate_stress <- compute_liability(
  lc_fits[[base_country]], lc_proj[[base_country]],
  r = R_STRESS, benefit = BENEFIT, ages_port = AGES_PORT
)

L_combined <- compute_liability(
  lc_fits[[base_country]], lc_proj_stress,
  r = R_STRESS, benefit = BENEFIT, ages_port = AGES_PORT
)

scenarios <- data.frame(
  Scenario       = c("Base Case",
                     "Mortality Stress (+15%)",
                     "Interest Rate Stress (-1%)",
                     "Combined Stress"),
  Liability_EUR  = format(round(c(L_base, L_mort_stress,
                                  L_rate_stress, L_combined)), big.mark = ","),
  Assets_EUR     = format(round(ASSETS), big.mark = ","),
  Solvency_Ratio = round(ASSETS / c(L_base, L_mort_stress,
                                    L_rate_stress, L_combined) * 100, 1)
)

cat("\n========================================\n")
cat("   SOLVENCY II STRESS TEST RESULTS\n")
cat("========================================\n\n")
print(scenarios, row.names = FALSE)

############################################################
# 9. PLOTS
############################################################

# --- Plot 1: Historical log death rates by country at age 65 ---
age_plot <- 65

hist_plot_df <- do.call(rbind, lapply(country_names, function(cn) {
  if (is.null(log_mx[[cn]])) return(NULL)
  mx_mat  <- log_mx[[cn]]
  age_idx <- which(rownames(mx_mat) == as.character(age_plot))
  if (length(age_idx) == 0) return(NULL)
  data.frame(
    Year    = as.numeric(colnames(mx_mat)),
    log_mx  = as.numeric(mx_mat[age_idx, ]),
    Country = cn
  )
}))

ggplot(hist_plot_df, aes(x = Year, y = log_mx, color = Country)) +
  geom_line(linewidth = 0.8) +
  labs(title    = paste("Historical Log Death Rates — Age", age_plot),
       subtitle = "Belgium, UK, Netherlands | 1970–2020",
       x = NULL, y = "Log Death Rate") +
  theme_minimal()

# --- Plot 2: Lee-Carter kt over time ---
kt_df <- do.call(rbind, lapply(country_names, function(cn) {
  if (is.null(lc_fits[[cn]])) return(NULL)
  data.frame(
    Year    = as.numeric(names(lc_fits[[cn]]$kt)),
    kt      = as.numeric(lc_fits[[cn]]$kt),
    Country = cn
  )
}))

ggplot(kt_df, aes(x = Year, y = kt, color = Country)) +
  geom_line(linewidth = 0.8) +
  labs(title    = "Lee-Carter Mortality Index (kt) Over Time",
       subtitle = "Downward trend = improving mortality",
       x = NULL, y = "kt") +
  theme_minimal()

# --- Plot 3: 30-year projection fan chart — Belgium age 65 ---
cn    <- "Belgium"
a_idx <- which(lc_fits[[cn]]$ages == age_plot)

proj_fan_df <- data.frame(
  Year    = lc_proj[[cn]]$years,
  Central = as.numeric(lc_proj[[cn]]$central[a_idx, ]),
  Lower   = as.numeric(lc_proj[[cn]]$lower[a_idx, ]),
  Upper   = as.numeric(lc_proj[[cn]]$upper[a_idx, ]),
  Model   = "Lee-Carter"
)

cbd_fan_df <- data.frame(
  Year    = cbd_proj[[cn]]$years,
  Central = as.numeric(cbd_proj[[cn]]$central[a_idx, ]),
  Lower   = as.numeric(cbd_proj[[cn]]$lower[a_idx, ]),
  Upper   = as.numeric(cbd_proj[[cn]]$upper[a_idx, ]),
  Model   = "CBD"
)

fan_df <- rbind(proj_fan_df, cbd_fan_df)

ggplot(fan_df, aes(x = Year, color = Model, fill = Model)) +
  geom_ribbon(aes(ymin = Lower, ymax = Upper), alpha = 0.2, color = NA) +
  geom_line(aes(y = Central), linewidth = 1) +
  labs(title    = paste("30-Year Mortality Projection — Belgium, Age", age_plot),
       subtitle = "Shaded area = 90% confidence interval from 1,000 simulations",
       x = NULL, y = "Projected Death Rate") +
  theme_minimal()

# --- Plot 4: Solvency ratio under stress scenarios ---
scenarios_plot <- data.frame(
  Scenario       = c("Base Case",
                     "Mortality Stress (+15%)",
                     "Interest Rate Stress (-1%)",
                     "Combined Stress"),
  Solvency_Ratio = round(ASSETS / c(L_base, L_mort_stress,
                                    L_rate_stress, L_combined) * 100, 1)
)

ggplot(scenarios_plot,
       aes(x = reorder(Scenario, -Solvency_Ratio),
           y = Solvency_Ratio,
           fill = Solvency_Ratio >= 100)) +
  geom_col(alpha = 0.85) +
  geom_hline(yintercept = 100, linetype = "dashed",
             color = "red", linewidth = 1) +
  scale_fill_manual(values = c("TRUE"  = "steelblue",
                               "FALSE" = "firebrick"),
                    guide = "none") +
  coord_flip() +
  labs(title    = "Solvency II Stress Test — Life Insurer",
       subtitle = "Red line = 100% minimum solvency threshold",
       x = NULL, y = "Solvency Ratio (%)") +
  theme_minimal()

# --- Plot 5: Model comparison RMSE by country ---
comp_long <- comparison_df %>%
  select(Country, LC_RMSE, CBD_RMSE) %>%
  pivot_longer(cols = c(LC_RMSE, CBD_RMSE),
               names_to = "Model", values_to = "RMSE") %>%
  mutate(Model = ifelse(Model == "LC_RMSE", "Lee-Carter", "CBD"))

ggplot(comp_long, aes(x = Country, y = RMSE, fill = Model)) +
  geom_col(position = "dodge", alpha = 0.85) +
  scale_fill_manual(values = c("Lee-Carter" = "steelblue",
                               "CBD"        = "firebrick")) +
  labs(title    = "Model Fit Comparison: Lee-Carter vs CBD",
       subtitle = "RMSE — lower is better",
       x = NULL, y = "Root Mean Squared Error") +
  theme_minimal()

############################################################
# END
############################################################
############################################################
# SECTIONS 10–12: EXTENDED ANALYSIS
# Paste these after Section 9 in your existing script.
# All sections reuse variables already computed above.
############################################################

############################################################
# 10. LONGEVITY VAR — 99.5TH PERCENTILE LIABILITY
############################################################
# Instead of a fixed +15% shock, we compute the liability at the
# 99.5th percentile of all 1,000 simulated mortality paths.
# The 99.5th percentile means: in only 1 out of 200 years would
# mortality be this bad or worse — exactly the Solvency II threshold.
# This is how internal models work in practice, and is more
# sophisticated than the standard formula stress we ran in Section 8.

cat("\n--- Longevity VaR (99.5th Percentile) ---\n")

# For each simulation path, compute the total portfolio liability
# using that path's projected death rates instead of the central projection
n_sim_stored <- dim(lc_proj[[base_country]]$sims)[3]

sim_liabilities <- rep(NA, n_sim_stored)

for (s in 1:n_sim_stored) {
  
  # Extract one simulated mortality path — a matrix of death rates
  # dim = (ages x projection years) for simulation s
  sim_mx <- lc_proj[[base_country]]$sims[, , s]
  
  # Wrap it in the same structure as lc_projection$central
  # so we can reuse compute_liability without changes
  sim_proj <- list(central = sim_mx)
  
  sim_liabilities[s] <- tryCatch(
    compute_liability(lc_fits[[base_country]], sim_proj,
                      r = R_BASE, benefit = BENEFIT,
                      ages_port = AGES_PORT),
    error = function(e) NA
  )
}

sim_liabilities <- sim_liabilities[!is.na(sim_liabilities)]

# 99.5th percentile liability = worst case in 1-in-200 year event
L_var995 <- quantile(sim_liabilities, 0.995)
L_var95  <- quantile(sim_liabilities, 0.95)
L_median <- quantile(sim_liabilities, 0.50)

solvency_var <- round(ASSETS / L_var995 * 100, 1)

cat("Median Liability (50th pct) : EUR", format(round(L_median), big.mark = ","), "\n")
cat("Stressed Liability (95th pct): EUR", format(round(L_var95),  big.mark = ","), "\n")
cat("VaR Liability (99.5th pct)  : EUR", format(round(L_var995), big.mark = ","), "\n")
cat("Solvency Ratio at VaR 99.5% :", solvency_var, "%\n")
cat("Capital shortfall (EUR)     :", format(round(max(0, L_var995 - ASSETS)), big.mark = ","), "\n")

# Plot the full distribution of simulated liabilities
sim_lib_df <- data.frame(Liability = sim_liabilities)

ggplot(sim_lib_df, aes(x = Liability)) +
  geom_histogram(bins = 60, fill = "steelblue", alpha = 0.7, color = "white") +
  geom_vline(xintercept = L_base,   color = "black",    linetype = "solid",  linewidth = 1) +
  geom_vline(xintercept = ASSETS,   color = "darkgreen", linetype = "dashed", linewidth = 1) +
  geom_vline(xintercept = L_var995, color = "firebrick", linetype = "dashed", linewidth = 1) +
  annotate("text", x = L_base,   y = Inf, label = "Base",   vjust = 2, hjust = -0.1, size = 3) +
  annotate("text", x = ASSETS,   y = Inf, label = "Assets", vjust = 3.5, hjust = -0.1, size = 3, color = "darkgreen") +
  annotate("text", x = L_var995, y = Inf, label = "VaR 99.5%", vjust = 2, hjust = -0.1, size = 3, color = "firebrick") +
  scale_x_continuous(labels = comma) +
  labs(
    title    = "Distribution of Simulated Liabilities — Belgium",
    subtitle = "1,000 Monte Carlo paths | Red = 99.5th percentile (Solvency II threshold)",
    x = "Total Portfolio Liability (EUR)", y = "Count"
  ) +
  theme_minimal()

############################################################
# 11. MULTI-COUNTRY LIABILITY COMPARISON
############################################################
# We run the same insurer portfolio under UK and Netherlands
# mortality assumptions to show how geography affects liability.
# A UK insurer holding the same policies faces a different liability
# than a Belgian insurer simply because mortality rates differ.
# This connects the three-country mortality analysis to the ALM output.

cat("\n--- Multi-Country Liability Comparison ---\n")

country_liabilities <- data.frame()

for (cn in country_names) {
  if (is.null(lc_fits[[cn]]) || is.null(lc_proj[[cn]])) next
  
  L_cn <- compute_liability(
    lc_fits[[cn]], lc_proj[[cn]],
    r = R_BASE, benefit = BENEFIT, ages_port = AGES_PORT
  )
  
  # Mortality stress per country
  proj_stress_cn         <- lc_proj[[cn]]
  proj_stress_cn$central <- proj_stress_cn$central * 1.15
  
  L_cn_stress <- compute_liability(
    lc_fits[[cn]], proj_stress_cn,
    r = R_BASE, benefit = BENEFIT, ages_port = AGES_PORT
  )
  
  # Interest rate stress per country
  L_cn_rate <- compute_liability(
    lc_fits[[cn]], lc_proj[[cn]],
    r = R_STRESS, benefit = BENEFIT, ages_port = AGES_PORT
  )
  
  country_liabilities <- rbind(country_liabilities, data.frame(
    Country          = cn,
    Base_Liability   = round(L_cn),
    Mort_Stress_Lib  = round(L_cn_stress),
    Rate_Stress_Lib  = round(L_cn_rate),
    Base_Solvency    = round(ASSETS / L_cn * 100, 1),
    Mort_Solvency    = round(ASSETS / L_cn_stress * 100, 1),
    Rate_Solvency    = round(ASSETS / L_cn_rate * 100, 1)
  ))
}

print(country_liabilities, row.names = FALSE)

# Plot solvency ratio by country and scenario
sol_long <- country_liabilities %>%
  select(Country, Base_Solvency, Mort_Solvency, Rate_Solvency) %>%
  pivot_longer(cols = c(Base_Solvency, Mort_Solvency, Rate_Solvency),
               names_to = "Scenario", values_to = "Solvency_Ratio") %>%
  mutate(Scenario = case_when(
    Scenario == "Base_Solvency" ~ "Base Case",
    Scenario == "Mort_Solvency" ~ "Mortality Stress",
    Scenario == "Rate_Solvency" ~ "Rate Stress"
  ))

ggplot(sol_long, aes(x = Country, y = Solvency_Ratio, fill = Scenario)) +
  geom_col(position = "dodge", alpha = 0.85) +
  geom_hline(yintercept = 100, linetype = "dashed", color = "red", linewidth = 1) +
  scale_fill_manual(values = c("Base Case"        = "steelblue",
                               "Mortality Stress" = "firebrick",
                               "Rate Stress"      = "darkorange")) +
  labs(
    title    = "Solvency Ratio by Country and Stress Scenario",
    subtitle = "Same insurer portfolio — different national mortality assumptions",
    x = NULL, y = "Solvency Ratio (%)"
  ) +
  theme_minimal()

############################################################
# 12. MORTALITY IMPROVEMENT TREND BY DECADE
############################################################
# We measure how much mortality improved in each decade from 1970 to 2020.
# Improvement rate at age x in decade d =
#   (log mx at end of decade - log mx at start of decade) / 10
# Negative = mortality improved (death rates fell) — the desired direction.
# If improvement is decelerating (getting less negative each decade),
# the model's drift projection may be overly optimistic about the future.

cat("\n--- Mortality Improvement by Decade ---\n")

decades <- list(
  "1970s" = c(1970, 1980),
  "1980s" = c(1980, 1990),
  "1990s" = c(1990, 2000),
  "2000s" = c(2000, 2010),
  "2010s" = c(2010, 2020)
)

improvement_df <- data.frame()

for (cn in country_names) {
  if (is.null(log_mx[[cn]])) next
  
  mx_mat <- log_mx[[cn]]
  years  <- as.numeric(colnames(mx_mat))
  
  for (dec_name in names(decades)) {
    y_start <- decades[[dec_name]][1]
    y_end   <- decades[[dec_name]][2]
    
    idx_start <- which(years == y_start)
    idx_end   <- which(years == y_end)
    
    if (length(idx_start) == 0 || length(idx_end) == 0) next
    
    # Average improvement across all ages 50-90
    # Negative value = mortality improved (rates fell)
    avg_improvement <- mean(
      (mx_mat[, idx_end] - mx_mat[, idx_start]) / 10
    )
    
    improvement_df <- rbind(improvement_df, data.frame(
      Country     = cn,
      Decade      = dec_name,
      Avg_Annual_Improvement = round(avg_improvement, 5)
    ))
  }
}

print(improvement_df, row.names = FALSE)

# Plot improvement by decade and country
ggplot(improvement_df, aes(x = Decade, y = Avg_Annual_Improvement,
                           color = Country, group = Country)) +
  geom_line(linewidth = 0.8) +
  geom_point(size = 3) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "black") +
  labs(
    title    = "Mortality Improvement Rate by Decade",
    subtitle = "Average annual log death rate change across ages 50–90 | More negative = faster improvement",
    x = NULL, y = "Avg Annual Change in Log Death Rate"
  ) +
  theme_minimal()

############################################################
# END OF EXTENDED ANALYSIS
############################################################