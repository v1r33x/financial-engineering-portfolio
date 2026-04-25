
# INTEREST RATE RISK MODELLING
# Yield Curve Dynamics, Duration Management & Portfolio VaR
# Models: Nelson-Siegel, Svensson, Vasicek
# Data  : ECB Euro Area Sovereign Bonds
# Output: Duration/convexity, KRD, immunisation,
#         stress testing, stochastic VaR



# 0. LIBRARIES

library(tidyverse)   # data manipulation and plotting
library(ggplot2)     # plots
library(scales)      # axis formatting


# 1. YIELD CURVE DATA

# ECB AAA-rated government bond zero-coupon yields
# approximated from published ECB data (end-2024).
# Three historical scenarios for stress testing.

maturities  <- c(0.25, 0.5, 1, 2, 3, 5, 7, 10, 15, 20, 30)

# Base: end-2024 inverted-then-normal curve shape
yields_2024 <- c(3.45, 3.35, 3.10, 2.75, 2.65, 2.60, 2.65, 2.70, 2.80, 2.85, 2.90)

# 2022 rate shock: ECB tightening cycle, upward-sloping
yields_2022 <- c(1.80, 2.20, 2.60, 2.90, 3.00, 3.05, 3.10, 3.15, 3.20, 3.25, 3.30)

# 2008 crisis: flight to safety, low short rates, normal long end
yields_2008 <- c(3.80, 3.60, 3.20, 3.00, 3.10, 3.30, 3.50, 3.70, 3.90, 4.00, 4.10)

cat("--- Yield Curve Data ---\n")
yield_df <- data.frame(
  Maturity   = maturities,
  Y2024      = yields_2024,
  Y2022      = yields_2022,
  Y2008      = yields_2008
)
print(yield_df, row.names = FALSE)


# 2. NELSON-SIEGEL MODEL

# Decomposes the yield curve into three factors:
# beta0 = long-run level (yield at infinite maturity)
# beta1 = short-term slope (difference short vs long end)
# beta2 = medium-term curvature (hump in the middle)
# lambda = decay speed (controls where hump peaks)
#
# Fitted by non-linear least squares to observed yields.
# RMSE < 0.05% is considered a good fit for sovereign curves.

fit_ns_grid <- function(maturities, yields) {
  # Sweep lambda on a grid — for each lambda, betas are solved by OLS
  # This avoids the local minima problem of direct NLS optimization
  lambda_grid <- seq(0.2, 10, by = 0.1)
  best_rmse   <- Inf
  best_params <- NULL
  
  for (lam in lambda_grid) {
    f1 <- (1 - exp(-maturities/lam)) / (maturities/lam)
    f2 <- f1 - exp(-maturities/lam)
    X  <- cbind(1, f1, f2)
    
    # OLS: yields = X %*% [beta0, beta1, beta2]
    fit  <- tryCatch(lm(yields ~ f1 + f2), error = function(e) NULL)
    if (is.null(fit)) next
    
    rmse <- sqrt(mean(residuals(fit)^2))
    if (rmse < best_rmse) {
      best_rmse   <- rmse
      best_params <- c(coef(fit), lam)
      names(best_params) <- c("beta0","beta1","beta2","lambda")
    }
  }
  best_params
}

params_2024 <- fit_ns_grid(maturities, yields_2024)
params_2022 <- fit_ns_grid(maturities, yields_2022)
params_2008 <- fit_ns_grid(maturities, yields_2008)


# 3. SVENSSON MODEL (4-FACTOR EXTENSION)

# Adds a second curvature term (beta3, lambda2) to Nelson-Siegel.
# Better handles complex curve shapes (double humps).
# ECB publishes official Svensson parameters daily.

svensson <- function(m, beta0, beta1, beta2, beta3, lam1, lam2) {
  f1 <- (1 - exp(-m/lam1)) / (m/lam1)
  f2 <- f1 - exp(-m/lam1)
  f3 <- (1 - exp(-m/lam2)) / (m/lam2) - exp(-m/lam2)
  beta0 + beta1*f1 + beta2*f2 + beta3*f3
}

fit_sv <- tryCatch(
  nls(yields_2024 ~ svensson(maturities, b0, b1, b2, b3, l1, l2),
      start = list(b0=2.9, b1=0.7, b2=-2.3, b3=0, l1=1.8, l2=5),
      control = nls.control(maxiter = 1000, warnOnly = TRUE)),
  error = function(e) NULL
)

if (!is.null(fit_sv)) {
  sv_params   <- coef(fit_sv)
  sv_fitted   <- svensson(maturities, sv_params[1], sv_params[2],
                          sv_params[3], sv_params[4], sv_params[5], sv_params[6])
  sv_rmse     <- sqrt(mean((sv_fitted - yields_2024)^2))
  ns_fitted   <- nelson_siegel(maturities, params_2024[1], params_2024[2],
                               params_2024[3], params_2024[4])
  ns_rmse     <- sqrt(mean((ns_fitted - yields_2024)^2))
  cat("\n--- Svensson vs Nelson-Siegel Fit ---\n")
  cat("NS RMSE      :", round(ns_rmse, 5), "%\n")
  cat("Svensson RMSE:", round(sv_rmse, 5), "%\n")
  cat("Improvement  :", round((ns_rmse - sv_rmse)/ns_rmse*100, 1), "%\n")
}


# 4. BOND PORTFOLIO

# Five European sovereign bonds — one per issuer.
# Face value EUR 10M each. Coupon = approximate market coupon.
# YTM read from Nelson-Siegel fitted curve.
# Duration and convexity computed analytically.

bonds <- data.frame(
  name     = c("Germany 2Y","France 5Y","Italy 7Y","Spain 10Y","Germany 30Y"),
  face     = rep(10e6, 5),
  coupon   = c(2.75, 2.60, 2.65, 2.70, 2.90),  # %
  maturity = c(2, 5, 7, 10, 30),
  # Credit spreads over German Bund (basis points)
  # Reflects sovereign risk — Italy/Spain trade wider than Germany
  spread_bps = c(0, 45, 130, 80, 0),
  stringsAsFactors = FALSE
)

bond_price <- function(face, coupon_pct, maturity, ytm_pct) {
  # Present value of coupon annuity + face value
  # All payments discounted at yield to maturity
  c   <- face * coupon_pct/100
  ytm <- ytm_pct/100
  n   <- maturity
  if (ytm == 0) return(c * n + face)
  c * (1 - (1+ytm)^(-n)) / ytm + face * (1+ytm)^(-n)
}

modified_duration_fn <- function(face, coupon_pct, maturity, ytm_pct) {
  c     <- face * coupon_pct/100
  ytm   <- ytm_pct/100
  n     <- as.integer(maturity)
  price <- bond_price(face, coupon_pct, maturity, ytm_pct)
  
  mac <- 0
  for (t in 1:n) {
    mac <- mac + t * c * (1+ytm)^(-t)
  }
  mac <- mac + n * face * (1+ytm)^(-n)
  mac <- mac / price
  mod <- mac / (1 + ytm)
  
  # Return as plain named list not vector — avoids NA from name collision
  list(mac_dur = as.numeric(mac), mod_dur = as.numeric(mod))
}

convexity_fn <- function(face, coupon_pct, maturity, ytm_pct) {
  # Convexity corrects for the non-linearity of price-yield relationship
  # Duration alone underestimates gains and overestimates losses for large shocks
  c     <- face * coupon_pct/100
  ytm   <- ytm_pct/100
  n     <- maturity
  price <- bond_price(face, coupon_pct, maturity, ytm_pct)
  conv  <- sum(sapply(1:n, function(t) t*(t+1) * c * (1+ytm)^(-(t+2))))
  conv  <- conv + n*(n+1) * face * (1+ytm)^(-(n+2))
  conv  / price
}

# Compute stats for each bond using base curve + credit spread
cat("\n--- Bond Portfolio ---\n")

bond_stats <- lapply(1:nrow(bonds), function(i) {
  b       <- bonds[i, ]
  base_ytm <- nelson_siegel(b$maturity, params_2024[1], params_2024[2],
                            params_2024[3], params_2024[4])
  ytm     <- base_ytm + b$spread_bps/100
  price   <- bond_price(b$face, b$coupon, b$maturity, ytm)
  durs    <- modified_duration_fn(b$face, b$coupon, b$maturity, ytm)
  conv    <- convexity_fn(b$face, b$coupon, b$maturity, ytm)
  list(name=b$name, price=price, ytm=ytm, mac_dur=durs["mac_dur"],
       mod_dur=durs["mod_dur"], conv=conv)
})

port_df <- data.frame(
  Bond      = sapply(bond_stats, `[[`, "name"),
  Price_M   = round(sapply(bond_stats, function(s) as.numeric(s$price))/1e6, 4),
  YTM_pct   = round(sapply(bond_stats, function(s) as.numeric(s$ytm)), 3),
  Mac_Dur   = round(sapply(bond_stats, function(s) as.numeric(s$mac_dur)), 3),
  Mod_Dur   = round(sapply(bond_stats, function(s) as.numeric(s$mod_dur)), 3),
  Convexity = round(sapply(bond_stats, function(s) as.numeric(s$conv)), 3)
)
print(port_df, row.names = FALSE)

total_value  <- sum(sapply(bond_stats, function(s) as.numeric(s$price)))
port_mod_dur <- sum(sapply(bond_stats, function(s) as.numeric(s$price) * as.numeric(s$mod_dur))) / total_value
port_conv    <- sum(sapply(bond_stats, function(s) as.numeric(s$price) * as.numeric(s$conv)))    / total_value

cat(sprintf("\nPortfolio value    : EUR %.3fM\n", total_value/1e6))
cat(sprintf("Portfolio duration : %.3f years\n", port_mod_dur))
cat(sprintf("Portfolio convexity: %.3f\n", port_conv))


# 5. KEY RATE DURATION

# Parallel shift assumes all maturities move equally — unrealistic.
# Key Rate Duration (KRD) measures sensitivity to a shock at
# one specific maturity point, holding others constant.
# Sum of KRDs should approximate modified duration.

cat("\n--- Key Rate Duration ---\n")

key_rates <- c(1, 2, 5, 10, 30)
shock_size <- 0.01  # 100 bps shock at each key rate

krd_results <- sapply(key_rates, function(kr) {
  # Tent function shock: peaks at kr, tapers to 0 at adjacent key rates
  shock_vec <- sapply(maturities, function(m) {
    if (m <= kr) {
      prev_kr <- max(c(0, key_rates[key_rates < kr]))
      if (kr > prev_kr) shock_size * max(0, (m - prev_kr)/(kr - prev_kr)) else shock_size
    } else {
      next_kr <- min(key_rates[key_rates > kr])
      if (length(next_kr) > 0 && next_kr > kr)
        shock_size * max(0, (next_kr - m)/(next_kr - kr))
      else 0
    }
  })
  
  shocked_yields <- yields_2024 + shock_vec
  
  # Reprice all bonds under shocked curve
  new_total <- sum(sapply(1:nrow(bonds), function(i) {
    b       <- bonds[i, ]
    base    <- approx(maturities, shocked_yields, xout = b$maturity)$y
    new_ytm <- base + b$spread_bps/100
    bond_price(b$face, b$coupon, b$maturity, new_ytm)
  }))
  
  pnl <- new_total - total_value
  krd <- -(pnl / total_value) / shock_size
  c(KRD = krd, PnL_M = pnl/1e6)
})

krd_df <- data.frame(
  Key_Rate = paste0(key_rates, "Y"),
  KRD      = round(krd_results["KRD", ], 3),
  PnL_M    = round(krd_results["PnL_M", ], 4)
)
print(krd_df, row.names = FALSE)
cat("Sum of KRDs:", round(sum(krd_results["KRD",]), 3),
    "(should ≈ modified duration", round(port_mod_dur, 3), ")\n")

# Plot KRD profile
ggplot(krd_df, aes(x = Key_Rate, y = KRD)) +
  geom_col(fill = "steelblue", alpha = 0.85) +
  labs(title    = "Key Rate Duration Profile",
       subtitle = "Sensitivity to 100bps shock at each maturity point",
       x = "Key Rate", y = "Key Rate Duration (years)") +
  theme_minimal()


# 6. STRESS TESTING

# Six scenarios covering parallel shifts, historical events,
# and non-parallel curve movements (steepening/flattening).

cat("\n--- Stress Testing ---\n")

stress_scenarios <- list(
  "2022 Rate Shock"       = yields_2022,
  "2008 Crisis"           = yields_2008,
  "Parallel +200bps"      = yields_2024 + 2.0,
  "Parallel -100bps"      = yields_2024 - 1.0,
  "Steepening +200bps LT" = yields_2024 + seq(0, 2, length.out=length(maturities)),
  "Flattening +200bps ST" = yields_2024 + seq(2, 0, length.out=length(maturities))
)

stress_results <- lapply(names(stress_scenarios), function(nm) {
  sc_yields <- stress_scenarios[[nm]]
  new_total <- sum(sapply(1:nrow(bonds), function(i) {
    b       <- bonds[i, ]
    new_ytm <- approx(maturities, sc_yields, xout = b$maturity)$y + b$spread_bps/100
    bond_price(b$face, b$coupon, b$maturity, new_ytm)
  }))
  pnl    <- new_total - total_value
  ret    <- pnl / total_value * 100
  data.frame(Scenario = nm, Value_M = round(new_total/1e6,3),
             PnL_M = round(pnl/1e6,3), Return_pct = round(ret,2))
})

stress_df <- do.call(rbind, stress_results)
print(stress_df, row.names = FALSE)

# Plot stress P&L
ggplot(stress_df, aes(x = reorder(Scenario, PnL_M), y = PnL_M,
                      fill = PnL_M >= 0)) +
  geom_col(alpha = 0.85) +
  geom_hline(yintercept = 0, linetype = "dashed") +
  coord_flip() +
  scale_fill_manual(values = c("TRUE" = "steelblue", "FALSE" = "firebrick"),
                    guide = "none") +
  labs(title    = "Portfolio P&L Under Stress Scenarios",
       subtitle = "EUR 50M bond portfolio | Blue = gain, Red = loss",
       x = NULL, y = "P&L (EUR M)") +
  theme_minimal()


# 7. DURATION APPROXIMATION ACCURACY

# Validates the duration + convexity approximation against
# full revaluation. Shows where the approximation breaks down.
# dP/P ≈ -D*dy + 0.5*C*(dy)^2

cat("\n--- Duration Approximation Accuracy ---\n")

shocks <- c(-2.0, -1.0, -0.5, -0.25, 0.25, 0.5, 1.0, 2.0)

approx_df <- do.call(rbind, lapply(shocks, function(shock_pct) {
  shocked <- yields_2024 + shock_pct
  new_total <- sum(sapply(1:nrow(bonds), function(i) {
    b       <- bonds[i, ]
    new_ytm <- approx(maturities, shocked, xout = b$maturity)$y + b$spread_bps/100
    bond_price(b$face, b$coupon, b$maturity, new_ytm)
  }))
  true_pnl <- new_total - total_value
  dy       <- shock_pct / 100
  approx_pnl <- (-port_mod_dur * dy + 0.5 * port_conv * dy^2) * total_value
  error_bps  <- (approx_pnl - true_pnl) / total_value * 10000
  data.frame(Shock_pct = shock_pct, True_PnL_M = round(true_pnl/1e6,3),
             Approx_PnL_M = round(approx_pnl/1e6,3),
             Error_bps = round(error_bps,1))
}))

print(approx_df, row.names = FALSE)


# 8. IMMUNISATION

# Duration immunisation: set asset duration = liability duration
# so that a small parallel rate shift leaves surplus unchanged.
# Convexity matching provides second-order protection.

cat("\n--- Immunisation Analysis ---\n")

L_value    <- 50e6
L_duration <- 8.0
L_convexity <- 80.0

dollar_dur_assets  <- total_value * port_mod_dur
dollar_dur_liab    <- L_value    * L_duration
duration_gap       <- port_mod_dur - (L_value / total_value) * L_duration

cat(sprintf("Asset duration       : %.3f years\n", port_mod_dur))
cat(sprintf("Liability duration   : %.3f years\n", L_duration))
cat(sprintf("Asset convexity      : %.3f\n", port_conv))
cat(sprintf("Liability convexity  : %.3f\n", L_convexity))
cat(sprintf("Dollar duration gap  : EUR %.2fM\n", (dollar_dur_assets - dollar_dur_liab)/1e6))
cat(sprintf("Duration gap         : %.3f years\n", duration_gap))

if (abs(duration_gap) < 0.5) {
  cat("Status: IMMUNISED (gap within 0.5 year tolerance)\n")
} else {
  cat("Status: NOT IMMUNISED — rebalancing required\n")
}

if (port_conv > L_convexity) {
  cat("Convexity: assets > liabilities — positive convexity advantage\n")
} else {
  cat("Convexity: assets < liabilities — liability convexity exceeds assets\n")
}


# 9. VASICEK STOCHASTIC RATE MODEL

# dr = kappa*(theta - r)*dt + sigma*dW
# Mean-reverting: rates pulled toward theta with speed kappa.
# Allows Monte Carlo simulation of future rate paths.
# Portfolio VaR computed from distribution of 1-year outcomes.

cat("\n--- Vasicek Stochastic Rate Model ---\n")

# Calibration to approximate ECB short rate history 2013-2024
hist_rates <- c(0.25, 0.05, 0.00, -0.40, -0.40, -0.50,
                -0.50, 0.00, 2.50, 3.50, 4.00, 3.50)
dt_ann <- 1.0
dr     <- diff(hist_rates)
r_lag  <- head(hist_rates, -1)

# OLS: dr = alpha + beta*r_lag => kappa = -beta, theta = alpha/kappa
fit_vasicek <- lm(dr ~ r_lag)
alpha_ols   <- coef(fit_vasicek)[1]
beta_ols    <- coef(fit_vasicek)[2]

kappa <- max(0.1, min(-beta_ols, 5.0))
theta <- max(0.5, min(alpha_ols / kappa, 8.0))
sigma <- max(0.3, min(sd(residuals(fit_vasicek)), 3.0))
r0    <- tail(hist_rates, 1)

cat(sprintf("kappa (mean reversion): %.4f\n", kappa))
cat(sprintf("theta (long-run mean) : %.4f%%\n", theta))
cat(sprintf("sigma (volatility)    : %.4f%%\n", sigma))
cat(sprintf("r0    (current rate)  : %.2f%%\n", r0))

# Monte Carlo simulation
set.seed(42)
N_SIM   <- 5000
N_STEPS <- 120   # 10 years monthly
dt_m    <- 1/12

paths <- matrix(NA, N_SIM, N_STEPS + 1)
paths[, 1] <- r0

for (t in 1:N_STEPS) {
  dW        <- rnorm(N_SIM, 0, sqrt(dt_m))
  dr_sim    <- kappa * (theta - paths[, t]/100) * dt_m * 100 + sigma * dW * sqrt(100)
  # Simplified discretisation for illustration
  dr_sim    <- kappa * (theta/100 - paths[,t]/100) * dt_m * 100 + sigma/100 * rnorm(N_SIM) * sqrt(dt_m) * 100
  paths[, t+1] <- pmax(paths[, t] + dr_sim, -2.0)
}

cat("\nSimulated short rate distribution:\n")
for (h in c(12, 36, 60, 120)) {
  r_h <- paths[, h+1]
  cat(sprintf("%2dY: mean=%.2f%% | 5th=%.2f%% | median=%.2f%% | 95th=%.2f%%\n",
              h/12, mean(r_h), quantile(r_h,.05), median(r_h), quantile(r_h,.95)))
}

# Portfolio VaR under stochastic rates (1-year horizon)
r_1y <- paths[, 13]

port_vals_1y <- sapply(r_1y, function(r_sim) {
  rate_shift  <- r_sim - r0
  new_yields  <- yields_2024 + rate_shift
  sum(sapply(1:nrow(bonds), function(i) {
    b       <- bonds[i, ]
    new_ytm <- approx(maturities, new_yields, xout = b$maturity)$y + b$spread_bps/100
    bond_price(b$face, b$coupon, b$maturity, new_ytm)
  }))
})

losses_1y <- total_value - port_vals_1y

cat(sprintf("\nStochastic Portfolio VaR (1-year, %d simulations):\n", N_SIM))
cat(sprintf("Expected P&L  : EUR %.3fM\n",  -mean(losses_1y)/1e6))
cat(sprintf("VaR 95%%      : EUR %.3fM loss\n", quantile(losses_1y, 0.95)/1e6))
cat(sprintf("VaR 99%%      : EUR %.3fM loss\n", quantile(losses_1y, 0.99)/1e6))
cat(sprintf("CVaR 99%%     : EUR %.3fM loss\n",
            mean(losses_1y[losses_1y >= quantile(losses_1y, 0.99)])/1e6))

# Plot loss distribution
loss_df <- data.frame(Loss = losses_1y / 1e6)
var99 <- quantile(losses_1y, 0.99) / 1e6

ggplot(loss_df, aes(x = Loss)) +
  geom_histogram(bins = 60, fill = "steelblue", alpha = 0.7, color = "white") +
  geom_vline(xintercept = 0, linetype = "solid", color = "black") +
  geom_vline(xintercept = var99, linetype = "dashed", color = "firebrick", linewidth = 1) +
  annotate("text", x = var99, y = Inf, label = "VaR 99%",
           vjust = 2, hjust = -0.1, color = "firebrick", size = 3) +
  labs(title    = "Portfolio Loss Distribution — Vasicek Stochastic Rates",
       subtitle = paste0("1-year horizon | ", N_SIM, " Monte Carlo simulations"),
       x = "Portfolio Loss (EUR M)", y = "Count") +
  theme_minimal()


# 10. CREDIT SPREAD STRESS

# Peripheral sovereign spreads (Italy, Spain) can widen
# significantly in stress. Quantify impact on portfolio value.

cat("\n--- Credit Spread Stress ---\n")

spread_scenarios <- list(
  "Base"                   = c(0,  45,  130,  80, 0),
  "Italy +100bps"          = c(0,  45,  230,  80, 0),
  "Peripheral crisis +200" = c(0,  95,  330, 180, 0),
  "Full crisis +300"       = c(0, 145,  430, 280, 0)
)

for (nm in names(spread_scenarios)) {
  spreads  <- spread_scenarios[[nm]]
  new_total <- sum(sapply(1:nrow(bonds), function(i) {
    b       <- bonds[i, ]
    base_ytm <- nelson_siegel(b$maturity, params_2024[1], params_2024[2],
                              params_2024[3], params_2024[4])
    new_ytm  <- base_ytm + spreads[i]/100
    bond_price(b$face, b$coupon, b$maturity, new_ytm)
  }))
  pnl <- new_total - total_value
  cat(sprintf("%-30s : EUR %6.3fM  (P&L: %+.3fM)\n", nm, new_total/1e6, pnl/1e6))
}


# END

cat("\n--- Project complete ---\n")
cat("Outputs: Nelson-Siegel fit, Svensson comparison, bond portfolio,\n")
cat("         KRD profile, stress tests, immunisation, Vasicek VaR,\n")
cat("         credit spread sensitivity\n")