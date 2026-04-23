############################################################
# CREDIT RISK MODELLING — MERTON STRUCTURAL MODEL
# Universe   : European large-caps, cross-sector (9 companies)
# Models     : Snapshot Merton, MLE Merton, Empirical PD
# Portfolio  : Gaussian copula, 3 correlation scenarios
# Output     : DD, PD, credit spreads, portfolio VaR
############################################################

############################################################
# 0. LIBRARIES
############################################################
library(quantmod)    # download stock price data
library(tidyverse)   # data manipulation and plotting
library(ggplot2)     # plots
library(scales)      # axis formatting
library(Matrix)      # nearPD for valid correlation matrices

############################################################
# 1. COMPANY DATA
############################################################
# Total debt = short-term + long-term debt from annual reports (EUR M)
# Shares outstanding in millions
# Maturity = average debt maturity in years (3-4 standard assumption)

companies <- data.frame(
  name     = c("ASML","Siemens","TotalEnergies","BNP Paribas",
               "Volkswagen","LVMH","Bayer","Unilever","Airbus"),
  ticker   = c("ASML.AS","SIE.DE","TTE.PA","BNP.PA",
               "VOW3.DE","MC.PA","BAYN.DE","UNA.AS","AIR.PA"),
  sector   = c("Technology","Industrials","Energy","Financials",
               "Automotive","Luxury","Healthcare","Consumer","Industrials"),
  debt_eur = c(3200, 38000, 58000, 950000,
               192000, 18000, 35000, 24000, 15000),
  shares_m = c(415, 800, 2660, 1270, 498, 502, 982, 2600, 777),
  maturity = c(3, 3, 4, 3, 3, 3, 4, 3, 4),
  stringsAsFactors = FALSE
)

cat("Companies loaded:", nrow(companies), "\n")
print(companies[, c("name","sector","debt_eur","shares_m")])

############################################################
# 2. DOWNLOAD STOCK PRICES
############################################################
cat("\nDownloading stock prices...\n")

getSymbols(companies$ticker, from = "2022-01-01",
           src = "yahoo", auto.assign = TRUE)

price_list <- lapply(companies$ticker, function(tk) {
  tryCatch(Ad(get(tk)), error = function(e) { cat("Failed:", tk, "\n"); NULL })
})
names(price_list) <- companies$ticker
price_list <- Filter(Negate(is.null), price_list)

companies <- companies[companies$ticker %in% names(price_list), ]
cat("Successfully downloaded:", nrow(companies), "companies\n")

############################################################
# 3. MARKET EQUITY AND EQUITY VOLATILITY
############################################################
# Market equity = latest price x shares outstanding
# Equity volatility = annualised std dev of daily log returns
# Annualise by sqrt(252) — 252 trading days per year

compute_equity_stats <- function(prices, shares_m) {
  latest_price  <- as.numeric(tail(prices, 1))
  market_equity <- latest_price * shares_m
  log_returns   <- as.numeric(na.omit(diff(log(prices))))
  sigma_E       <- sd(log_returns) * sqrt(252)
  list(price = latest_price, market_equity = market_equity, sigma_E = sigma_E)
}

equity_stats <- lapply(seq_len(nrow(companies)), function(i)
  compute_equity_stats(price_list[[companies$ticker[i]]], companies$shares_m[i]))

companies$price         <- sapply(equity_stats, `[[`, "price")
companies$market_equity <- sapply(equity_stats, `[[`, "market_equity")
companies$sigma_E       <- sapply(equity_stats, `[[`, "sigma_E")

cat("\n--- Equity Statistics ---\n")
print(companies[, c("name","price","market_equity","sigma_E")], row.names = FALSE)

############################################################
# 4. SNAPSHOT MERTON
############################################################
# Uses only today's equity and equity volatility as inputs.
# Iterative solver finds asset value (A) and asset volatility (sigma_A)
# that simultaneously satisfy two Merton equations.
# Equity is a call option on assets: E = A*N(d1) - D*exp(-rT)*N(d2)
# Volatility link: sigma_E*E = N(d1)*sigma_A*A

RF_RATE <- 0.03   # risk-free rate

merton_solve <- function(E, sigma_E, D, T, r,
                         max_iter = 1000, tol = 1e-6) {
  A       <- E + D
  sigma_A <- sigma_E * E / A
  
  for (iter in 1:max_iter) {
    A_old       <- A
    sigma_A_old <- sigma_A
    
    d1 <- (log(A/D) + (r + 0.5*sigma_A^2)*T) / (sigma_A*sqrt(T))
    d2 <- d1 - sigma_A*sqrt(T)
    
    A <- E + D*exp(-r*T)*pnorm(d2)/pnorm(d1) *
      exp((r + 0.5*sigma_A^2)*T - log(A/D)/(sigma_A*sqrt(T)))
    sigma_A <- sigma_E * E / (pnorm(d1) * A)
    
    if (is.na(A) || is.na(sigma_A) || A <= 0 || sigma_A <= 0) {
      A <- E + D; sigma_A <- sigma_E; break
    }
    if (abs(A - A_old)/A_old < tol &&
        abs(sigma_A - sigma_A_old)/sigma_A_old < tol) break
  }
  
  d1 <- (log(A/D) + (r + 0.5*sigma_A^2)*T) / (sigma_A*sqrt(T))
  d2 <- d1 - sigma_A*sqrt(T)
  DD <- d2
  PD <- pnorm(-d2)
  bond_value    <- max(D*exp(-r*T)*(1-PD), 1e-6)
  credit_spread <- -log(bond_value / (D*exp(-r*T))) / T
  
  list(A = A, sigma_A = sigma_A, DD = DD, PD = PD,
       credit_spread = credit_spread)
}

cat("\nRunning Snapshot Merton...\n")

snap_results <- lapply(seq_len(nrow(companies)), function(i)
  tryCatch(
    merton_solve(companies$market_equity[i], companies$sigma_E[i],
                 companies$debt_eur[i], companies$maturity[i], RF_RATE),
    error = function(e) NULL))

companies$DD            <- sapply(snap_results, function(r) if (!is.null(r)) r$DD    else NA)
companies$PD            <- sapply(snap_results, function(r) if (!is.null(r)) r$PD    else NA)
companies$credit_spread <- sapply(snap_results, function(r) if (!is.null(r)) r$credit_spread else NA)
companies$asset_value   <- sapply(snap_results, function(r) if (!is.null(r)) r$A     else NA)
companies$leverage      <- companies$debt_eur / companies$asset_value

cat("\n--- Snapshot Merton Results ---\n")
output_snap <- companies %>%
  mutate(DD          = round(DD, 3),
         PD_pct      = round(PD * 100, 3),
         Spread_bps  = round(credit_spread * 10000, 1),
         Leverage_pct = round(leverage * 100, 1)) %>%
  select(name, sector, DD, PD_pct, Spread_bps, Leverage_pct) %>%
  arrange(DD)
print(output_snap, row.names = FALSE)

############################################################
# 5. MLE MERTON
############################################################
# Inverts Merton call option formula for EVERY daily equity value
# in the 2-year price history, giving a time series of implied asset values.
# sigma_A = std dev of implied daily asset log returns (annualised).
# Outer loop iterates until sigma_A converges — typically 5-10 iterations.
# More stable than snapshot because it uses ~500 data points not just 2.

bs_call <- function(A, D, r, T, sigma_A) {
  if (sigma_A <= 0 || A <= 0 || T <= 0) return(NA)
  d1   <- (log(A/D) + (r + 0.5*sigma_A^2)*T) / (sigma_A*sqrt(T))
  d2   <- d1 - sigma_A*sqrt(T)
  A*pnorm(d1) - D*exp(-r*T)*pnorm(d2)
}

merton_invert_daily <- function(E, D, r, T, sigma_A) {
  if (is.na(E) || E <= 0) return(NA)
  f     <- function(A) bs_call(A, D, r, T, sigma_A) - E
  lower <- D * 0.01
  upper <- E + D * 10
  f_lo  <- tryCatch(f(lower), error = function(e) NA)
  f_up  <- tryCatch(f(upper), error = function(e) NA)
  if (is.na(f_lo) || is.na(f_up) || f_lo*f_up > 0) return(NA)
  tryCatch(uniroot(f, lower=lower, upper=upper, tol=1e-6)$root,
           error = function(e) NA)
}

mle_merton <- function(equity_series, D, r, T, shares_m,
                       max_outer = 20, tol = 1e-4) {
  E_series <- as.numeric(equity_series) * shares_m
  E_series <- E_series[!is.na(E_series) & E_series > 0]
  if (length(E_series) < 50) return(NULL)
  
  E_last  <- tail(E_series, 1)
  sigma_E <- sd(diff(log(E_series)), na.rm = TRUE) * sqrt(252)
  sigma_A <- sigma_E * E_last / (E_last + D)
  
  for (outer in 1:max_outer) {
    sigma_A_old <- sigma_A
    A_series    <- sapply(E_series, function(E)
      merton_invert_daily(E, D, r, T, sigma_A))
    A_series    <- A_series[!is.na(A_series) & A_series > 0]
    if (length(A_series) < 20) break
    sigma_A <- sd(diff(log(A_series)), na.rm = TRUE) * sqrt(252)
    if (is.na(sigma_A) || sigma_A <= 0) break
    if (abs(sigma_A - sigma_A_old)/sigma_A_old < tol) break
  }
  
  A_final <- tail(A_series, 1)
  d1 <- (log(A_final/D) + (r + 0.5*sigma_A^2)*T) / (sigma_A*sqrt(T))
  d2 <- d1 - sigma_A*sqrt(T)
  DD <- d2
  PD <- pnorm(-d2)
  bond_value    <- max(D*exp(-r*T)*(1-PD), 1e-6)
  credit_spread <- -log(bond_value / (D*exp(-r*T))) / T
  
  list(A=A_final, sigma_A=sigma_A, DD=DD, PD=PD,
       credit_spread=credit_spread, A_series=A_series)
}

cat("\nRunning MLE Merton (1-2 minutes)...\n")

mle_results <- lapply(seq_len(nrow(companies)), function(i) {
  cat("  Processing", companies$name[i], "...\n")
  mle_merton(price_list[[companies$ticker[i]]],
             companies$debt_eur[i], RF_RATE,
             companies$maturity[i], companies$shares_m[i])
})
names(mle_results) <- companies$name

companies$mle_DD    <- sapply(mle_results, function(r) if (!is.null(r)) r$DD    else NA)
companies$mle_PD    <- sapply(mle_results, function(r) if (!is.null(r)) r$PD    else NA)
companies$mle_spread <- sapply(mle_results, function(r) if (!is.null(r)) r$credit_spread else NA)
companies$mle_A     <- sapply(mle_results, function(r) if (!is.null(r)) r$A     else NA)

cat("\nDone.\n")

cat("\n--- Snapshot vs MLE Comparison ---\n")
comparison <- data.frame(
  Company      = companies$name,
  Snapshot_DD  = round(companies$DD, 3),
  MLE_DD       = round(companies$mle_DD, 3),
  Snapshot_PD  = round(companies$PD * 100, 3),
  MLE_PD       = round(companies$mle_PD * 100, 3),
  Snapshot_Spr = round(companies$credit_spread * 10000, 1),
  MLE_Spr      = round(companies$mle_spread * 10000, 1)
)
print(comparison, row.names = FALSE)

############################################################
# 6. EMPIRICAL PD FROM MOODY'S HISTORICAL DEFAULT RATES
############################################################
# Maps each company's MLE Distance to Default to a Moody's rating bucket.
# Assigns the historically observed default rate for that rating.
# This replaces theoretical N(-DD) with real-world default frequencies.
# Source: Moody's Annual Default Study 2023 (1-year averages 1983-2022)

moody_table <- data.frame(
  rating      = c("Aaa","Aa","A","Baa","Ba","B","Caa","Ca-C"),
  dd_lower    = c(6,    4,   3,  2,    1.5, 1,  0,    -Inf),
  dd_upper    = c(Inf,  6,   4,  3,    2,   1.5, 1,    0),
  hist_pd_pct = c(0.000, 0.013, 0.057, 0.166,
                  1.101, 4.378, 14.46, 30.0)
)

get_empirical_pd <- function(dd) {
  if (is.na(dd)) return(list(rating = NA, empirical_pd = NA))
  idx <- which(dd >= moody_table$dd_lower & dd < moody_table$dd_upper)
  if (length(idx) == 0) return(list(rating = "Ca-C", empirical_pd = 0.30))
  list(rating      = moody_table$rating[idx],
       empirical_pd = moody_table$hist_pd_pct[idx] / 100)
}

emp_results <- lapply(companies$mle_DD, get_empirical_pd)

companies$rating       <- sapply(emp_results, `[[`, "rating")
companies$empirical_pd <- sapply(emp_results, `[[`, "empirical_pd")

cat("\n--- Full Comparison: Snapshot vs MLE vs Empirical PD ---\n")
full_comparison <- data.frame(
  Company      = companies$name,
  Sector       = companies$sector,
  Rating       = companies$rating,
  MLE_DD       = round(companies$mle_DD, 2),
  Snapshot_PD  = round(companies$PD * 100, 3),
  MLE_PD       = round(companies$mle_PD * 100, 3),
  Empirical_PD = round(companies$empirical_pd * 100, 3)
) %>% arrange(MLE_DD)
print(full_comparison, row.names = FALSE)

############################################################
# 7. CORRELATION MATRIX
############################################################
# Real pairwise correlations from 2 years of daily equity returns.
# Used instead of flat 30% assumption — more realistic.

ret_matrix <- do.call(cbind, lapply(seq_len(nrow(companies)), function(i) {
  pr  <- as.numeric(price_list[[companies$ticker[i]]])
  ret <- diff(log(pr))
  ret[!is.finite(ret)] <- NA
  ret
}))
colnames(ret_matrix) <- companies$name

cor_matrix_real <- cor(ret_matrix, use = "pairwise.complete.obs")

cat("\n--- Real Pairwise Correlation Matrix ---\n")
print(round(cor_matrix_real, 2))

############################################################
# 8. PORTFOLIO VAR — THREE CORRELATION SCENARIOS
############################################################
# Gaussian copula portfolio credit VaR using empirical PDs.
# Base: real estimated correlations
# Stress: correlations blended 50% toward 1 (simulates crisis)
# Severe: all correlations set to 0.80 (extreme crisis)
# CVaR = expected loss in worst 1% of scenarios — better than VaR
# because it captures severity beyond the threshold, not just the threshold.

BOND_SIZE <- 10     # EUR millions per bond
RECOVERY  <- 0.40   # 40% recovery rate — 60% loss given default
N_SIM     <- 10000  # Monte Carlo simulations

run_portfolio_var <- function(pd_vec, cor_mat, bond_size,
                              recovery, n_sim, seed = 42) {
  set.seed(seed)
  cor_mat  <- as.matrix(nearPD(cor_mat, corr = TRUE)$mat)
  chol_mat <- chol(cor_mat)
  losses   <- rep(NA, n_sim)
  
  for (s in 1:n_sim) {
    z_corr   <- as.numeric(t(chol_mat) %*% rnorm(length(pd_vec)))
    defaults <- z_corr < qnorm(pd_vec)
    losses[s] <- sum(defaults) * bond_size * (1 - recovery)
  }
  
  list(expected = mean(losses),
       var99    = quantile(losses, 0.99),
       cvar99   = mean(losses[losses >= quantile(losses, 0.99)]),
       max      = max(losses),
       losses   = losses)
}

valid      <- !is.na(companies$empirical_pd)
pd_use     <- companies$empirical_pd[valid]
n_valid    <- sum(valid)
cor_base   <- cor_matrix_real[valid, valid]

# Stress: blend each correlation 50% toward 1
cor_stress <- cor_base
for (i in 1:n_valid) for (j in 1:n_valid)
  if (i != j) cor_stress[i,j] <- cor_base[i,j] + 0.5*(1 - cor_base[i,j])

# Severe: all off-diagonal = 0.80
cor_severe <- matrix(0.80, n_valid, n_valid)
diag(cor_severe) <- 1
rownames(cor_severe) <- rownames(cor_base)
colnames(cor_severe) <- colnames(cor_base)

cat("\nRunning portfolio VaR (3 scenarios)...\n")
var_base   <- run_portfolio_var(pd_use, cor_base,   BOND_SIZE, RECOVERY, N_SIM)
var_stress <- run_portfolio_var(pd_use, cor_stress, BOND_SIZE, RECOVERY, N_SIM)
var_severe <- run_portfolio_var(pd_use, cor_severe, BOND_SIZE, RECOVERY, N_SIM)

cat("\n========================================\n")
cat("   PORTFOLIO CREDIT VAR RESULTS\n")
cat("========================================\n")
cat("Total portfolio: EUR", n_valid * BOND_SIZE, "M\n\n")

scenarios_var <- data.frame(
  Scenario      = c("Base (Real)","Stress (50% toward 1)","Severe (All 80%)"),
  Expected_Loss = round(c(var_base$expected, var_stress$expected, var_severe$expected), 3),
  VaR_99        = round(c(var_base$var99,    var_stress$var99,    var_severe$var99),    2),
  CVaR_99       = round(c(var_base$cvar99,   var_stress$cvar99,   var_severe$cvar99),   2),
  Max_Loss      = round(c(var_base$max,      var_stress$max,      var_severe$max),      2)
)
print(scenarios_var, row.names = FALSE)

############################################################
# 9. PLOTS
############################################################

# --- Plot 1: Default Probability by Company (Snapshot) ---
ggplot(output_snap, aes(x = reorder(name, PD_pct), y = PD_pct, fill = sector)) +
  geom_col(alpha = 0.85) +
  coord_flip() +
  labs(title    = "Merton Default Probability by Company (Snapshot)",
       subtitle = "Annualised probability of default — risk-neutral",
       x = NULL, y = "Default Probability (%)", fill = "Sector") +
  theme_minimal()

# --- Plot 2: Distance to Default (Snapshot) ---
ggplot(output_snap, aes(x = reorder(name, -DD), y = DD, fill = sector)) +
  geom_col(alpha = 0.85) +
  geom_hline(yintercept = 1, linetype = "dashed",
             color = "red", linewidth = 0.8) +
  coord_flip() +
  labs(title    = "Distance to Default by Company",
       subtitle = "Red line = DD of 1 (danger zone below)",
       x = NULL, y = "Distance to Default", fill = "Sector") +
  theme_minimal()

# --- Plot 3: Credit Spread (Snapshot) ---
ggplot(output_snap, aes(x = reorder(name, Spread_bps),
                        y = Spread_bps, fill = sector)) +
  geom_col(alpha = 0.85) +
  coord_flip() +
  labs(title    = "Theoretical Credit Spread by Company",
       subtitle = "Basis points above risk-free rate | 1 bps = 0.01%",
       x = NULL, y = "Credit Spread (bps)", fill = "Sector") +
  theme_minimal()

# --- Plot 4: Snapshot vs MLE vs Empirical PD ---
pd_compare <- full_comparison %>%
  select(Company, Snapshot_PD, MLE_PD, Empirical_PD) %>%
  pivot_longer(cols = c(Snapshot_PD, MLE_PD, Empirical_PD),
               names_to = "Method", values_to = "PD_pct") %>%
  mutate(Method = factor(Method,
                         levels = c("Snapshot_PD","MLE_PD","Empirical_PD"),
                         labels = c("Snapshot","MLE","Empirical")))

ggplot(pd_compare, aes(x = reorder(Company, PD_pct),
                       y = PD_pct, fill = Method)) +
  geom_col(position = "dodge", alpha = 0.85) +
  coord_flip() +
  scale_fill_manual(values = c("Snapshot"  = "steelblue",
                               "MLE"       = "firebrick",
                               "Empirical" = "darkgreen")) +
  labs(title    = "Default Probability: Snapshot vs MLE vs Empirical",
       subtitle = "Empirical uses Moody's historical default rates by rating",
       x = NULL, y = "Default Probability (%)", fill = "Method") +
  theme_minimal()

# --- Plot 5: Rating assignment with DD thresholds ---
ggplot(full_comparison, aes(x = reorder(Company, MLE_DD),
                            y = MLE_DD, fill = Rating)) +
  geom_col(alpha = 0.85) +
  geom_hline(yintercept = 1, linetype="dashed", color="red",    linewidth=0.8) +
  geom_hline(yintercept = 2, linetype="dashed", color="orange", linewidth=0.6) +
  geom_hline(yintercept = 3, linetype="dashed", color="gold",   linewidth=0.6) +
  coord_flip() +
  labs(title    = "MLE Distance to Default with Moody's Rating",
       subtitle = "Red=B | Orange=BB | Gold=BBB threshold",
       x = NULL, y = "Distance to Default", fill = "Rating") +
  theme_minimal()

# --- Plot 6: Correlation heatmap ---
cor_df <- as.data.frame(cor_matrix_real) %>%
  rownames_to_column("Company1") %>%
  pivot_longer(-Company1, names_to="Company2", values_to="Correlation")

ggplot(cor_df, aes(x=Company1, y=Company2, fill=Correlation)) +
  geom_tile(color="white") +
  geom_text(aes(label=round(Correlation,2)), size=2.5) +
  scale_fill_gradient2(low="steelblue", mid="white", high="firebrick",
                       midpoint=0, limits=c(-1,1)) +
  labs(title    = "Equity Return Correlation Matrix",
       subtitle = "Estimated from 2 years of daily returns",
       x = NULL, y = NULL) +
  theme_minimal() +
  theme(axis.text.x = element_text(angle=45, hjust=1))

# --- Plot 7: Portfolio VaR across scenarios ---
var_long <- scenarios_var %>%
  select(Scenario, Expected_Loss, VaR_99, CVaR_99) %>%
  pivot_longer(cols=c(Expected_Loss, VaR_99, CVaR_99),
               names_to="Metric", values_to="Loss")

ggplot(var_long, aes(x=Scenario, y=Loss, fill=Metric)) +
  geom_col(position="dodge", alpha=0.85) +
  scale_fill_manual(values=c("Expected_Loss"="steelblue",
                             "VaR_99"="firebrick",
                             "CVaR_99"="darkorange")) +
  labs(title    = "Portfolio Credit VaR — Empirical PDs",
       subtitle = paste0("EUR ", n_valid*BOND_SIZE,
                         "M portfolio | Moody's calibrated default rates"),
       x = NULL, y = "Loss (EUR M)", fill = "Metric") +
  theme_minimal() +
  theme(axis.text.x=element_text(angle=15, hjust=1))

# --- Plot 8: Loss distribution overlay ---
loss_compare <- rbind(
  data.frame(Loss=var_base$losses,   Scenario="Base"),
  data.frame(Loss=var_stress$losses, Scenario="Stress"),
  data.frame(Loss=var_severe$losses, Scenario="Severe")
)

ggplot(loss_compare, aes(x=Loss, fill=Scenario)) +
  geom_density(alpha=0.4) +
  geom_vline(xintercept=var_base$var99,   color="steelblue", linetype="dashed") +
  geom_vline(xintercept=var_stress$var99, color="firebrick", linetype="dashed") +
  geom_vline(xintercept=var_severe$var99, color="darkorange", linetype="dashed") +
  scale_fill_manual(values=c("Base"="steelblue","Stress"="firebrick",
                             "Severe"="darkorange")) +
  labs(title    = "Portfolio Loss Distribution by Correlation Scenario",
       subtitle = "Dashed lines = VaR 99% per scenario",
       x = "Portfolio Loss (EUR M)", y = "Density", fill = "Scenario") +
  theme_minimal()

############################################################
# END
############################################################