
# WALK-FORWARD FACTOR MODEL
# Universe  : European Large-Caps (25 stocks)
# Factors   : Fama-French 5 + Momentum (12-1)
# Method    : Rolling 36-month OLS, predict next month alpha
# Output    : Long-short quintile portfolio, IC analysis

# 0. LIBRARIES
library(quantmod)
library(PerformanceAnalytics)
library(tidyverse)
library(lubridate)
library(zoo)
library(xts)


# 1. STOCK UNIVERSE — EUROPEAN LARGE-CAPS
assets <- c(
  # Technology / Semiconductors
  "ASML.AS", "IFX.DE", "SAP.DE",
  # Luxury & Consumer
  "MC.PA", "KER.PA", "OR.PA", "EL.PA",
  # Industrials
  "SIE.DE", "AIR.PA",
  # Automotive
  "VOW3.DE", "BMW.DE",
  # Financials
  "BNP.PA", "AXA.PA", "DBK.DE", "ALV.DE", "MUV2.DE", "UCG.MI",
  # Energy & Utilities
  "TTE.PA", "ENEL.MI", "IBE.MC",
  # Healthcare
  "SAN.PA", "BAYN.DE",
  # Telecom
  "DTE.DE", "ORAN.PA",
  # Food & Beverage
  "RI.PA"
)

# Download (2013 start — need extra history for 36-month training + momentum)
getSymbols(assets, from = "2013-01-01", src = "yahoo", auto.assign = TRUE)

# Build price matrix; skip any failed downloads gracefully
prices_list <- lapply(assets, function(x) {
  tryCatch(Ad(get(x)), error = function(e) NULL)
})
names(prices_list) <- assets
prices_list <- Filter(Negate(is.null), prices_list)
assets      <- names(prices_list)

prices <- do.call(merge, prices_list)
colnames(prices) <- assets

# Collapse to monthly (last trading day of each month)
prices_m <- to.monthly(prices, indexAt = "lastof", OHLC = FALSE)
prices_m <- na.omit(prices_m)


# 2. MONTHLY RETURNS
ret_m <- na.omit(Return.calculate(prices_m))


# 3. FAMA-FRENCH 5 FACTORS — EUROPEAN, MONTHLY

ff_url <- paste0(
  "https://mba.tuck.dartmouth.edu/pages/faculty/ken.french/",
  "ftp/Europe_5_Factors_CSV.zip"
)

tmp_zip <- tempfile(fileext = ".zip")
download.file(ff_url, tmp_zip, mode = "wb", quiet = TRUE)



# Read raw lines to find where numeric data begins
raw_lines <- readLines(unz(tmp_zip, "Europe_5_Factors.csv"))

# Detect first line that starts with a 6-digit year-month code
data_start <- which(grepl("^\\s*\\d{6}\\s*,", raw_lines))[1]

ff_raw <- read.csv(
  text = paste(raw_lines[data_start:length(raw_lines)], collapse = "\n"),
  header = FALSE,
  stringsAsFactors = FALSE
)

# Keep only rows where col 1 is exactly 6 digits (monthly, not annual)
ff_raw <- ff_raw[nchar(trimws(ff_raw[, 1])) == 6, ]

ff <- data.frame(
  ym    = trimws(ff_raw[, 1]),
  MktRF = as.numeric(ff_raw[, 2]) / 100,
  SMB   = as.numeric(ff_raw[, 3]) / 100,
  HML   = as.numeric(ff_raw[, 4]) / 100,
  RMW   = as.numeric(ff_raw[, 5]) / 100,
  CMA   = as.numeric(ff_raw[, 6]) / 100,
  RF    = as.numeric(ff_raw[, 7]) / 100
)

ff <- na.omit(ff)

# Convert YYYYMM → end-of-month date (to match xts monthly index)
ff$date <- as.Date(paste0(ff$ym, "01"), "%Y%m%d") %m+% months(1) - 1

ff_xts <- xts(ff[, c("MktRF","SMB","HML","RMW","CMA","RF")],
              order.by = ff$date)


# 4. MOMENTUM FACTOR (12-1 MONTH, CROSS-SECTIONAL)
# For each stock at month t: return from t-12 to t-2 (skip t-1)
# Implemented as: 11-month cumulative return ending 2 months ago
mom <- xts::lag.xts(prices_m, 1) / xts::lag.xts(prices_m, 12) - 1
colnames(mom) <- assets


# 5. ALIGN DATE INDICES
common_idx <- Reduce(function(a, b) a[a %in% b],
                     list(index(ret_m), index(ff_xts), index(mom)))

ret_m  <- ret_m[common_idx, ]
ff_xts <- ff_xts[common_idx, ]
mom    <- mom[common_idx, ]

n_dates  <- length(common_idx)
n_stocks <- ncol(ret_m)


# 6. WALK-FORWARD: ROLLING ALPHA ESTIMATION
# For each month t, train OLS on [t-36 : t-1], extract alpha per stock.
# Alpha = expected return unexplained by systematic factors.
# We rank stocks by alpha → long-short quintile portfolio next month.

TRAIN_WIN <- 36   # rolling training window in months

alpha_mat <- matrix(NA, nrow = n_dates, ncol = n_stocks,
                    dimnames = list(as.character(common_idx), assets))

for (t in (TRAIN_WIN + 1):n_dates) {
  
  idx_train <- (t - TRAIN_WIN):(t - 1)
  
  ff_tr  <- ff_xts[idx_train, ]
  ret_tr <- ret_m[idx_train, ]
  mom_tr <- mom[idx_train, ]
  
  # Common factor matrix (shared across stocks)
  X_common <- data.frame(
    MktRF = as.numeric(ff_tr$MktRF),
    SMB   = as.numeric(ff_tr$SMB),
    HML   = as.numeric(ff_tr$HML),
    RMW   = as.numeric(ff_tr$RMW),
    CMA   = as.numeric(ff_tr$CMA)
  )
  
  for (s in seq_len(n_stocks)) {
    
    # Excess return
    y <- as.numeric(ret_tr[, s]) - as.numeric(ff_tr$RF)
    
    # Stock-specific momentum regressor
    mom_s <- as.numeric(mom_tr[, s])
    
    df <- data.frame(y = y, X_common, MOM = mom_s)
    df <- df[complete.cases(df), ]
    
    if (nrow(df) < 24) next   # need at least 24 obs for stable estimates
    
    fit <- tryCatch(lm(y ~ ., data = df), error = function(e) NULL)
    if (is.null(fit)) next
    
    alpha_mat[t, s] <- coef(fit)[1]   # annualise below if needed
  }
}


# 7. LONG-SHORT QUINTILE PORTFOLIO
# At end of month t, rank stocks by estimated alpha → 
# form portfolio held over month t+1.

port_ret   <- rep(NA, n_dates)
ic_series  <- rep(NA, n_dates)

for (t in (TRAIN_WIN + 1):(n_dates - 1)) {
  
  alpha_t    <- alpha_mat[t, ]
  realized_t <- as.numeric(ret_m[t + 1, ])
  
  valid <- !is.na(alpha_t) & !is.na(realized_t)
  if (sum(valid) < 10) next
  
  av <- alpha_t[valid]
  rv <- realized_t[valid]
  
  # Quintile breakpoints
  q <- quantile(av, probs = c(0.2, 0.8))
  
  long_mask  <- av >= q[2]
  short_mask <- av <= q[1]
  
  if (sum(long_mask) == 0 || sum(short_mask) == 0) next
  
  port_ret[t + 1] <- mean(rv[long_mask]) - mean(rv[short_mask])
  
  # IC: rank correlation of predicted alpha vs realized return
  ic_series[t + 1] <- cor(av, rv, method = "spearman")
}

port_xts <- xts(port_ret, order.by = common_idx)
port_xts <- na.omit(port_xts)

ic_xts <- xts(ic_series, order.by = common_idx)
ic_xts <- na.omit(ic_xts)


# 8. IC DECAY ANALYSIS (horizons 1–6 months)
MAX_H    <- 6
ic_decay <- rep(NA, MAX_H)

for (h in 1:MAX_H) {
  
  ic_h <- rep(NA, n_dates)
  
  for (t in (TRAIN_WIN + 1):(n_dates - h)) {
    
    alpha_t    <- alpha_mat[t, ]
    realized_t <- as.numeric(ret_m[t + h, ])
    
    valid <- !is.na(alpha_t) & !is.na(realized_t)
    if (sum(valid) < 5) next
    
    ic_h[t] <- cor(alpha_t[valid], realized_t[valid], method = "spearman")
  }
  
  ic_decay[h] <- mean(ic_h, na.rm = TRUE)
}

ic_decay_df <- data.frame(
  Horizon = 1:MAX_H,
  Mean_IC = round(ic_decay, 4)
)


# 9. PERFORMANCE METRICS

cat("\n========================================\n")
cat("   WALK-FORWARD FACTOR MODEL RESULTS\n")
cat("========================================\n\n")

cat("--- Long-Short Portfolio ---\n")
cat("Annualized Sharpe :", round(SharpeRatio.annualized(port_xts), 3), "\n")
cat("Max Drawdown      :", round(maxDrawdown(port_xts), 3), "\n")
cat("Cumulative Return :", round(Return.cumulative(port_xts), 3), "\n\n")

cat("--- Information Coefficient ---\n")
cat("Mean IC           :", round(mean(ic_xts, na.rm = TRUE), 4), "\n")
cat("IC > 0 (hit rate) :", round(mean(ic_xts > 0, na.rm = TRUE) * 100, 1), "%\n")
cat("IC Std Dev        :", round(sd(ic_xts, na.rm = TRUE), 4), "\n\n")

cat("--- IC Decay by Forecast Horizon ---\n")
print(ic_decay_df)


# 10. PLOTS

# --- Plot 1: Long-Short Portfolio Performance ---
charts.PerformanceSummary(
  port_xts,
  main = "Long-Short Factor Portfolio (FF5 + Momentum)"
)

# --- Plot 2: IC Over Time ---
ic_df <- data.frame(
  date = index(ic_xts),
  IC   = as.numeric(ic_xts)
)

ggplot(ic_df, aes(x = date, y = IC)) +
  geom_line(color = "steelblue", linewidth = 0.6) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "red") +
  geom_smooth(method = "loess", se = FALSE, color = "orange", linewidth = 1) +
  labs(
    title    = "Information Coefficient Over Time",
    subtitle = "Spearman rank correlation: predicted alpha vs realized return",
    x = NULL, y = "IC"
  ) +
  theme_minimal()

# --- Plot 3: IC Decay ---
ggplot(ic_decay_df, aes(x = Horizon, y = Mean_IC)) +
  geom_col(fill = "steelblue", alpha = 0.8) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "red") +
  scale_x_continuous(breaks = 1:MAX_H) +
  labs(
    title    = "IC Decay by Forecast Horizon",
    subtitle = "Signal deterioration from month 1 to month 6",
    x = "Months Ahead", y = "Mean Spearman IC"
  ) +
  theme_minimal()


# END



# SECTIONS 11–15: EXTENDED ANALYSIS
# Paste these after Section 10 in your existing script.
# All sections reuse variables already computed above:
# alpha_mat, port_xts, ic_xts, ret_m, ff_xts, mom,
# common_idx, assets, n_dates, n_stocks, TRAIN_WIN



# 11. TURNOVER ANALYSIS

# Turnover = what fraction of the portfolio gets replaced each month.
# High turnover means frequent trading, which means high costs in practice.
# We measure it first so we can use it in Section 12 for cost adjustment.

# Reconstruct which stocks are long (+1), short (-1), or flat (0) each month
long_short_flags <- matrix(0, nrow = n_dates, ncol = n_stocks,
                           dimnames = list(as.character(common_idx), assets))

for (t in (TRAIN_WIN + 1):(n_dates - 1)) {
  alpha_t <- alpha_mat[t, ]
  valid   <- !is.na(alpha_t)
  if (sum(valid) < 10) next
  
  av <- alpha_t[valid]
  q  <- quantile(av, probs = c(0.2, 0.8))
  
  flags <- rep(0, n_stocks)
  flags[valid][av >= q[2]] <-  1   # long: top quintile
  flags[valid][av <= q[1]] <- -1   # short: bottom quintile
  
  long_short_flags[t, ] <- flags
}

# Compare each month's positions to previous month to count changes
# A position changing from long to flat, or flat to short, counts as one trade
turnover <- rep(NA, n_dates)

for (t in (TRAIN_WIN + 2):n_dates) {
  prev   <- long_short_flags[t - 1, ]
  curr   <- long_short_flags[t, ]
  changed <- sum(prev != curr)              # number of stocks that changed
  active  <- sum(prev != 0 | curr != 0)    # total stocks involved either month
  if (active > 0) turnover[t] <- changed / active
}

turnover_xts <- xts(turnover, order.by = common_idx)
turnover_xts <- na.omit(turnover_xts)

cat("\n--- Turnover Analysis ---\n")
cat("Mean Monthly Turnover:", round(mean(turnover_xts) * 100, 1), "%\n")
cat("Max  Monthly Turnover:", round(max(turnover_xts)  * 100, 1), "%\n\n")

# Plot turnover over time to see if rebalancing frequency changes
turnover_df <- data.frame(
  date     = index(turnover_xts),
  turnover = as.numeric(turnover_xts)
)

ggplot(turnover_df, aes(x = date, y = turnover)) +
  geom_line(color = "steelblue", linewidth = 0.6) +
  geom_smooth(method = "loess", se = FALSE, color = "orange", linewidth = 1) +
  scale_y_continuous(labels = scales::percent) +
  labs(
    title    = "Monthly Portfolio Turnover Over Time",
    subtitle = "Fraction of holdings replaced each month when rebalancing",
    x = NULL, y = "Turnover"
  ) +
  theme_minimal()


# 12. TRANSACTION COST SENSITIVITY

# We test how much of the strategy's return survives at different
# transaction cost levels. Cost is paid proportional to turnover —
# the more we trade, the more we pay.
# Net return = gross return - (turnover * cost per trade)
# This answers: at what cost level does the strategy break even?

# Rebuild gross portfolio returns aligned with turnover dates
port_ret_gross <- rep(NA, n_dates)

for (t in (TRAIN_WIN + 1):(n_dates - 1)) {
  alpha_t    <- alpha_mat[t, ]
  realized_t <- as.numeric(ret_m[t + 1, ])
  valid      <- !is.na(alpha_t) & !is.na(realized_t)
  if (sum(valid) < 10) next
  av <- alpha_t[valid]
  rv <- realized_t[valid]
  q  <- quantile(av, probs = c(0.2, 0.8))
  long_mask  <- av >= q[2]
  short_mask <- av <= q[1]
  if (sum(long_mask) == 0 || sum(short_mask) == 0) next
  port_ret_gross[t + 1] <- mean(rv[long_mask]) - mean(rv[short_mask])
}

# Test a range of costs from 0 to 200 basis points
# 1 basis point = 0.0001 (one hundredth of one percent)
cost_levels <- c(0, 0.001, 0.002, 0.005, 0.010, 0.020)

tc_results <- data.frame(
  Cost_bps   = cost_levels * 10000,
  Sharpe     = NA,
  Cum_Return = NA
)

for (i in seq_along(cost_levels)) {
  tc    <- cost_levels[i]
  net   <- port_ret_gross - tc * turnover   # subtract cost * how much we traded
  net_x <- xts(net, order.by = common_idx)
  net_x <- na.omit(net_x)
  
  tc_results$Sharpe[i]     <- round(as.numeric(SharpeRatio.annualized(net_x)), 3)
  tc_results$Cum_Return[i] <- round(as.numeric(Return.cumulative(net_x)), 3)
}

cat("--- Transaction Cost Sensitivity ---\n")
print(tc_results)

ggplot(tc_results, aes(x = Cost_bps, y = Sharpe)) +
  geom_line(color = "steelblue", linewidth = 1) +
  geom_point(size = 3, color = "steelblue") +
  geom_hline(yintercept = 0, linetype = "dashed", color = "red") +
  labs(
    title    = "Strategy Sharpe vs Transaction Cost",
    subtitle = "At what cost level does the strategy stop being profitable?",
    x = "Transaction Cost (basis points per trade)",
    y = "Annualized Sharpe Ratio"
  ) +
  theme_minimal()


# 13. REGIME-CONDITIONAL PERFORMANCE

# We split every month into a market regime: Bull or Bear.
# Bull = the broad European market was up over the past 6 months.
# Bear = the broad European market was down over the past 6 months.
# This tells us whether the factor signal works in all conditions
# or only when markets are calm and rising.

# Use cumulative 6-month MktRF (market excess return) to define regime.
# Positive sum = bull market environment, negative = bear.
mkt_cum6 <- rollapply(ff_xts$MktRF, 6, sum, fill = NA, align = "right")
mkt_cum6 <- mkt_cum6[common_idx]

regime     <- ifelse(as.numeric(mkt_cum6) > 0, "Bull", "Bear")
regime_xts <- xts(regime, order.by = common_idx)

# Split IC by regime to see if signal quality changes with market environment
ic_df_regime <- data.frame(
  date   = index(ic_xts),
  IC     = as.numeric(ic_xts),
  regime = as.character(regime_xts[index(ic_xts)])
)

regime_ic_summary <- ic_df_regime %>%
  group_by(regime) %>%
  summarise(
    Mean_IC  = round(mean(IC, na.rm = TRUE), 4),
    Hit_Rate = paste0(round(mean(IC > 0, na.rm = TRUE) * 100, 1), "%"),
    N_Months = n(),
    .groups  = "drop"
  )

cat("\n--- Regime-Conditional IC ---\n")
print(regime_ic_summary)

# Split portfolio returns by regime to compare profitability
port_df <- data.frame(
  date   = index(port_xts),
  ret    = as.numeric(port_xts),
  regime = as.character(regime_xts[index(port_xts)])
)

regime_port_summary <- port_df %>%
  group_by(regime) %>%
  summarise(
    Mean_Monthly_Ret_pct = round(mean(ret, na.rm = TRUE) * 100, 2),
    Volatility_pct       = round(sd(ret, na.rm = TRUE) * 100, 2),
    .groups = "drop"
  )

cat("\n--- Regime-Conditional Portfolio Returns ---\n")
print(regime_port_summary)

ggplot(ic_df_regime, aes(x = date, y = IC, color = regime)) +
  geom_line(linewidth = 0.5, alpha = 0.8) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "black") +
  scale_color_manual(values = c("Bull" = "steelblue", "Bear" = "firebrick")) +
  labs(
    title    = "Information Coefficient by Market Regime",
    subtitle = "Bull = market up past 6 months | Bear = market down past 6 months",
    x = NULL, y = "Spearman IC", color = "Regime"
  ) +
  theme_minimal()


# 14. FACTOR CONTRIBUTION — LEAVE-ONE-OUT
# We re-run the entire walk-forward model 6 times, each time
# removing one factor from the regression. The drop in mean IC
# compared to the baseline tells us how much that factor contributes.
# If removing factor X barely changes IC, it adds little value.
# If IC collapses when X is removed, X is doing most of the work.
# NOTE: this section runs 6 full walk-forward loops and will take
# a few minutes — the same amount of time as the original Section 6.

all_factors <- c("MktRF", "SMB", "HML", "RMW", "CMA", "MOM")

loo_results <- data.frame(
  Factor_Dropped = c("None (baseline)", all_factors),
  Mean_IC        = NA
)

# Store baseline IC
loo_results$Mean_IC[1] <- round(mean(ic_xts, na.rm = TRUE), 4)

for (f_idx in seq_along(all_factors)) {
  
  drop_f    <- all_factors[f_idx]
  alpha_loo <- matrix(NA, nrow = n_dates, ncol = n_stocks)
  
  for (t in (TRAIN_WIN + 1):n_dates) {
    
    idx_tr <- (t - TRAIN_WIN):(t - 1)
    ff_tr  <- ff_xts[idx_tr, ]
    ret_tr <- ret_m[idx_tr, ]
    mom_tr <- mom[idx_tr, ]
    
    # Build factor matrix then remove the factor being tested
    X_base <- data.frame(
      MktRF = as.numeric(ff_tr$MktRF),
      SMB   = as.numeric(ff_tr$SMB),
      HML   = as.numeric(ff_tr$HML),
      RMW   = as.numeric(ff_tr$RMW),
      CMA   = as.numeric(ff_tr$CMA)
    )
    
    # Drop the FF factor column if it's one of the five FF factors
    if (drop_f != "MOM") {
      X_base <- X_base[, colnames(X_base) != drop_f, drop = FALSE]
    }
    
    for (s in seq_len(n_stocks)) {
      y     <- as.numeric(ret_tr[, s]) - as.numeric(ff_tr$RF)
      mom_s <- as.numeric(mom_tr[, s])
      
      # Include or exclude momentum depending on which factor we're dropping
      if (drop_f == "MOM") {
        df <- data.frame(y = y, X_base)
      } else {
        df <- data.frame(y = y, X_base, MOM = mom_s)
      }
      
      df  <- df[complete.cases(df), ]
      if (nrow(df) < 24) next
      fit <- tryCatch(lm(y ~ ., data = df), error = function(e) NULL)
      if (is.null(fit)) next
      alpha_loo[t, s] <- coef(fit)[1]
    }
  }
  
  # Compute IC for this leave-one-out model
  ic_loo <- rep(NA, n_dates)
  for (t in (TRAIN_WIN + 1):(n_dates - 1)) {
    a <- alpha_loo[t, ]
    r <- as.numeric(ret_m[t + 1, ])
    v <- !is.na(a) & !is.na(r)
    if (sum(v) < 5) next
    ic_loo[t] <- cor(a[v], r[v], method = "spearman")
  }
  
  loo_results$Mean_IC[f_idx + 1] <- round(mean(ic_loo, na.rm = TRUE), 4)
  cat("Done:", drop_f, "\n")   # progress indicator — one line per factor
}

# IC drop = how much worse is the model without each factor
loo_results$IC_Drop <- round(loo_results$Mean_IC[1] - loo_results$Mean_IC, 4)

cat("\n--- Factor Contribution (Leave-One-Out) ---\n")
print(loo_results)

ggplot(loo_results[-1, ], aes(x = reorder(Factor_Dropped, IC_Drop), y = IC_Drop)) +
  geom_col(fill = "steelblue", alpha = 0.8) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "red") +
  coord_flip() +   # horizontal bars are easier to read with factor names
  labs(
    title    = "Factor Contribution to Predictive Power",
    subtitle = "IC drop when each factor is removed — higher bar = more important",
    x = "Factor Removed", y = "Drop in Mean IC"
  ) +
  theme_minimal()


# 15. OUT-OF-SAMPLE TEST — FTSE 100 SUBSET
# We run the exact same model with the exact same parameters
# on a completely different universe: UK large-caps from the FTSE 100.
# No parameter changes are allowed — we use whatever worked in-sample.
# If Mean IC stays positive, the signal generalises across markets.
# If IC collapses to near zero, the signal was overfit to our original
# European universe and would not survive in live trading.

oos_assets <- c(
  "SHEL.L", "AZN.L",  "HSBA.L", "ULVR.L", "BP.L",
  "GSK.L",  "RIO.L",  "DGE.L",  "LLOY.L", "VOD.L",
  "BA.L",   "BARC.L", "IMB.L",  "NWG.L",  "PRU.L",
  "REL.L",  "RR.L",   "SSE.L",  "LSEG.L", "CPG.L"
)

getSymbols(oos_assets, from = "2013-01-01", src = "yahoo", auto.assign = TRUE)

oos_list <- lapply(oos_assets, function(x) {
  tryCatch(Ad(get(x)), error = function(e) NULL)
})
names(oos_list)   <- oos_assets
oos_list          <- Filter(Negate(is.null), oos_list)
oos_assets        <- names(oos_list)

oos_prices   <- do.call(merge, oos_list)
colnames(oos_prices) <- oos_assets

oos_prices_m <- to.monthly(oos_prices, indexAt = "lastof", OHLC = FALSE)
oos_prices_m <- na.omit(oos_prices_m)

oos_ret_m <- na.omit(Return.calculate(oos_prices_m))

# Build momentum for the FTSE universe using same 12-1 construction
oos_mom <- xts::lag.xts(oos_prices_m, 1) / xts::lag.xts(oos_prices_m, 12) - 1
colnames(oos_mom) <- oos_assets

# We reuse the same European FF5 factors — reasonable approximation for UK
oos_common <- Reduce(function(a, b) a[a %in% b],
                     list(index(oos_ret_m), index(ff_xts), index(oos_mom)))

oos_ret_m <- oos_ret_m[oos_common, ]
oos_ff    <- ff_xts[oos_common, ]
oos_mom   <- oos_mom[oos_common, ]

oos_n_dates  <- length(oos_common)
oos_n_stocks <- ncol(oos_ret_m)

# Walk-forward alpha estimation — identical structure to Section 6
oos_alpha <- matrix(NA, nrow = oos_n_dates, ncol = oos_n_stocks)

for (t in (TRAIN_WIN + 1):oos_n_dates) {
  idx_tr <- (t - TRAIN_WIN):(t - 1)
  ff_tr  <- oos_ff[idx_tr, ]
  ret_tr <- oos_ret_m[idx_tr, ]
  mom_tr <- oos_mom[idx_tr, ]
  
  X_c <- data.frame(
    MktRF = as.numeric(ff_tr$MktRF),
    SMB   = as.numeric(ff_tr$SMB),
    HML   = as.numeric(ff_tr$HML),
    RMW   = as.numeric(ff_tr$RMW),
    CMA   = as.numeric(ff_tr$CMA)
  )
  
  for (s in seq_len(oos_n_stocks)) {
    y     <- as.numeric(ret_tr[, s]) - as.numeric(ff_tr$RF)
    mom_s <- as.numeric(mom_tr[, s])
    df    <- data.frame(y = y, X_c, MOM = mom_s)
    df    <- df[complete.cases(df), ]
    if (nrow(df) < 24) next
    fit   <- tryCatch(lm(y ~ ., data = df), error = function(e) NULL)
    if (is.null(fit)) next
    oos_alpha[t, s] <- coef(fit)[1]
  }
}

# Compute IC for the FTSE universe
oos_ic <- rep(NA, oos_n_dates)
for (t in (TRAIN_WIN + 1):(oos_n_dates - 1)) {
  a <- oos_alpha[t, ]
  r <- as.numeric(oos_ret_m[t + 1, ])
  v <- !is.na(a) & !is.na(r)
  if (sum(v) < 5) next
  oos_ic[t] <- cor(a[v], r[v], method = "spearman")
}

oos_ic_xts <- xts(oos_ic, order.by = oos_common)
oos_ic_xts <- na.omit(oos_ic_xts)

cat("\n--- Out-of-Sample Test: FTSE 100 Subset ---\n")
cat("Original European Universe:\n")
cat("  Mean IC  :", round(mean(ic_xts, na.rm = TRUE), 4), "\n")
cat("  Hit Rate :", round(mean(ic_xts > 0, na.rm = TRUE) * 100, 1), "%\n\n")
cat("FTSE 100 Universe (out-of-sample):\n")
cat("  Mean IC  :", round(mean(oos_ic_xts, na.rm = TRUE), 4), "\n")
cat("  Hit Rate :", round(mean(oos_ic_xts > 0, na.rm = TRUE) * 100, 1), "%\n")

# Compare IC distributions side by side
ic_compare <- rbind(
  data.frame(date = index(ic_xts),     IC = as.numeric(ic_xts),     Universe = "European"),
  data.frame(date = index(oos_ic_xts), IC = as.numeric(oos_ic_xts), Universe = "FTSE 100")
)

ggplot(ic_compare, aes(x = IC, fill = Universe)) +
  geom_density(alpha = 0.5) +
  geom_vline(xintercept = 0, linetype = "dashed") +
  scale_fill_manual(values = c("European" = "steelblue", "FTSE 100" = "firebrick")) +
  labs(
    title    = "IC Distribution: Original vs Out-of-Sample",
    subtitle = "Same model, same parameters — different stock universe",
    x = "Spearman IC", y = "Density"
  ) +
  theme_minimal()

############################################################
# END OF EXTENDED ANALYSIS
############################################################
