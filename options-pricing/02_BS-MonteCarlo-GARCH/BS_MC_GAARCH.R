
# ASML OPTIONS PRICING ENGINE
# Comparing: GARCH(1,1) vs Historical Vol vs Implied Vol
# Data: Yahoo Finance (quantmod) | Maturities: 30 / 60 / 90 days

packages <- c("RQuantLib", "quantmod", "rugarch", "ggplot2",
              "dplyr", "tidyr", "gridExtra", "zoo")
installed <- packages %in% rownames(installed.packages())
if (any(!installed)) install.packages(packages[!installed])

library(RQuantLib)
library(quantmod)
library(rugarch)
library(ggplot2)
library(dplyr)
library(tidyr)
library(gridExtra)
library(zoo)

set.seed(42)


# SECTION 1: FETCH ASML DATA FROM YAHOO FINANCE

cat("=== Fetching ASML data from Yahoo Finance ===\n")

# ASML trades as ASML.AS on Euronext Amsterdam
getSymbols("ASML.AS", src = "yahoo",
           from = Sys.Date() - 365,
           to   = Sys.Date(),
           auto.assign = TRUE)

prices  <- Cl(ASML.AS)                        # closing prices
prices  <- na.omit(prices)
returns <- na.omit(diff(log(prices)))          # log returns

S <- as.numeric(tail(prices, 1))              # latest spot price
r <- 0.035                                    # ECB rate approx

cat("Spot price (latest close) : €", round(S, 2), "\n")
cat("Number of trading days    :", nrow(returns), "\n")
cat("Date range                :", as.character(index(returns)[1]),
    "to", as.character(index(returns)[nrow(returns)]), "\n\n")


# SECTION 2: VOLATILITY ESTIMATION


# 2a. Historical Volatility 
# Annualised std dev of log returns over full 1-year window
hist_vol_annual <- as.numeric(sd(returns)) * sqrt(252)

# Rolling 30-day historical vol (for the vol comparison plot)
roll_vol <- rollapply(returns, width = 30,
                      FUN    = function(x) sd(x) * sqrt(252),
                      align  = "right", fill = NA)

cat("=== Volatility Estimates ===\n")
cat("Historical Vol (1yr)      :", round(hist_vol_annual, 4), "\n")

# Specify GARCH(1,1) with normal innovations
spec <- ugarchspec(
  variance.model = list(model = "sGARCH", garchOrder = c(1, 1)),
  mean.model     = list(armaOrder = c(0, 0), include.mean = TRUE),
  distribution.model = "norm"
)

# Fit to 1 year of log returns
fit <- ugarchfit(spec = spec, data = returns, solver = "hybrid")

cat("\n=== GARCH(1,1) Coefficients ===\n")
print(round(coef(fit), 6))

# Persistence = alpha + beta (should be < 1 for stationarity)
alpha <- coef(fit)["alpha1"]
beta  <- coef(fit)["beta1"]
omega <- coef(fit)["omega"]
persistence <- alpha + beta
cat("\nPersistence (alpha+beta)  :", round(persistence, 4),
    ifelse(persistence < 1, "✓ stationary", "⚠ non-stationary"), "\n")

# Unconditional (long-run) variance
uncond_vol <- sqrt(omega / (1 - persistence)) * sqrt(252)
cat("Unconditional (LR) Vol    :", round(uncond_vol, 4), "\n")

# Forecast volatility for 30, 60, 90 days ahead
fc_90 <- ugarchforecast(fit, n.ahead = 90)
sigma_daily <- as.numeric(sigma(fc_90))      # daily vol forecast, 90 steps

# Annualise average daily vol over each horizon (term structure)
garch_vol <- list(
  "30" = mean(sigma_daily[1:30])  * sqrt(252),
  "60" = mean(sigma_daily[1:60])  * sqrt(252),
  "90" = mean(sigma_daily[1:90])  * sqrt(252)
)

cat("\n=== GARCH Forecasted Vol (annualised) ===\n")
cat("30-day horizon            :", round(garch_vol[["30"]], 4), "\n")
cat("60-day horizon            :", round(garch_vol[["60"]], 4), "\n")
cat("90-day horizon            :", round(garch_vol[["90"]], 4), "\n")


# SECTION 3: PRICING FUNCTIONS

bs_price <- function(S, K, T, r, sigma) {
  as.numeric(tryCatch(
    EuropeanOption("call", S, K, 0, r, T, sigma)$value,
    error = function(e) NA_real_
  ))
}

implied_vol <- function(price, S, K, T, r, init_vol = 0.2) {
  as.numeric(tryCatch(
    EuropeanOptionImpliedVolatility("call", price, S, K, 0, r, T, init_vol),
    error = function(e) NA_real_
  ))
}

mc_price <- function(S, K, T, r, sigma, n_sim = 100000) {
  Z  <- rnorm(n_sim)
  ST <- S * exp((r - 0.5 * sigma^2) * T + sigma * sqrt(T) * Z)
  exp(-r * T) * mean(pmax(ST - K, 0))
}

get_greeks <- function(S, K, T, r, sigma) {
  opt <- tryCatch(EuropeanOption("call", S, K, 0, r, T, sigma),
                  error = function(e) NULL)
  if (is.null(opt)) return(list(delta=NA,gamma=NA,vega=NA,theta=NA))
  list(delta=as.numeric(opt$delta), gamma=as.numeric(opt$gamma),
       vega=as.numeric(opt$vega),   theta=as.numeric(opt$theta))
}


# SECTION 4: BUILD PRICING SURFACE
# Strike range: ±20% around spot, 11 strikes

strikes    <- round(seq(S * 0.80, S * 1.20, length.out = 11), 0)
maturities <- c(30, 60, 90)

cat("\n=== Strike Range ===\n")
cat("Strikes:", strikes, "\n")

# For each maturity, price using all three vol methods
all_data <- do.call(rbind, lapply(maturities, function(days) {
  T_i      <- days / 365
  garch_s  <- garch_vol[[as.character(days)]]
  hist_s   <- hist_vol_annual
  
  do.call(rbind, lapply(strikes, function(K) {
    
    price_garch <- bs_price(S, K, T_i, r, garch_s)
    price_hist  <- bs_price(S, K, T_i, r, hist_s)
    
    # IV-based: use GARCH price as "market" proxy, extract IV, reprice
    # (simulates what IV engine would do with a real market quote)
    iv_val  <- implied_vol(price_garch + rnorm(1, 0, 0.3), S, K, T_i, r)
    price_iv <- if (!is.na(iv_val)) bs_price(S, K, T_i, r, iv_val) else NA_real_
    
    # MC under GARCH vol
    price_mc <- mc_price(S, K, T_i, r, garch_s)
    
    # Greeks under GARCH vol
    g <- get_greeks(S, K, T_i, r, garch_s)
    
    data.frame(
      Maturity     = paste0(days, "d"),
      Days         = days,
      Strike       = K,
      Moneyness    = round(K / S, 3),
      GARCH_Vol    = round(garch_s,  4),
      Hist_Vol     = round(hist_s,   4),
      IV           = round(iv_val,   4),
      Price_GARCH  = round(price_garch, 4),
      Price_Hist   = round(price_hist,  4),
      Price_IV     = round(price_iv,    4),
      Price_MC     = round(price_mc,    4),
      Delta        = round(g$delta, 4),
      Gamma        = round(g$gamma, 4),
      Vega         = round(g$vega,  4),
      Theta        = round(g$theta, 4)
    )
  }))
}))

cat("\n=== Full Pricing Surface Preview ===\n")
print(all_data %>% select(Maturity, Strike, Moneyness,
                          GARCH_Vol, Hist_Vol, IV,
                          Price_GARCH, Price_Hist, Price_IV, Price_MC))


# SECTION 5: PLOTS


# --- Plot 1: ASML Price + Rolling Vol (data quality check) ------
prices_df <- data.frame(
  Date  = index(prices),
  Price = as.numeric(prices)
)
roll_df <- data.frame(
  Date    = index(roll_vol),
  RollVol = as.numeric(roll_vol)
) %>% filter(!is.na(RollVol))

p_price <- ggplot(prices_df, aes(x = Date, y = Price)) +
  geom_line(color = "#1F4E79", linewidth = 0.8) +
  labs(title = "ASML.AS — 1 Year Price History",
       subtitle = paste("Latest close: €", round(S, 2)),
       x = NULL, y = "Price (€)") +
  theme_minimal(base_size = 11) +
  theme(plot.title = element_text(face = "bold"))

p_rollvol <- ggplot(roll_df, aes(x = Date, y = RollVol)) +
  geom_line(color = "#E74C3C", linewidth = 0.8) +
  geom_hline(yintercept = hist_vol_annual, linetype = "dashed",
             color = "#1F4E79", linewidth = 0.7) +
  geom_hline(yintercept = garch_vol[["30"]], linetype = "dashed",
             color = "#27AE60", linewidth = 0.7) +
  annotate("text", x = roll_df$Date[10], y = hist_vol_annual + 0.01,
           label = paste0("Hist Vol: ", round(hist_vol_annual*100,1), "%"),
           color = "#1F4E79", size = 3) +
  annotate("text", x = roll_df$Date[10], y = garch_vol[["30"]] - 0.015,
           label = paste0("GARCH 30d: ", round(garch_vol[["30"]]*100,1), "%"),
           color = "#27AE60", size = 3) +
  labs(title = "30-day Rolling Realised Volatility",
       subtitle = "vs Historical (blue) and GARCH forecast (green)",
       x = NULL, y = "Annualised Vol") +
  theme_minimal(base_size = 11) +
  theme(plot.title = element_text(face = "bold"))


fc_df <- data.frame(
  Day     = 1:90,
  GARCH   = sigma_daily * sqrt(252),
  Hist    = rep(hist_vol_annual, 90)
)

p_garch_fc <- ggplot(fc_df, aes(x = Day)) +
  geom_line(aes(y = GARCH, color = "GARCH Forecast"), linewidth = 1) +
  geom_line(aes(y = Hist,  color = "Historical Vol"), linewidth = 0.8,
            linetype = "dashed") +
  geom_hline(yintercept = uncond_vol, color = "#F39C12",
             linetype = "dotted", linewidth = 0.8) +
  annotate("text", x = 75, y = uncond_vol + 0.005,
           label = paste0("LR Mean: ", round(uncond_vol*100,1), "%"),
           color = "#F39C12", size = 3) +
  scale_color_manual(values = c("GARCH Forecast" = "#27AE60",
                                "Historical Vol"  = "#1F4E79")) +
  labs(title = "GARCH(1,1) Volatility Forecast — 90 Days Ahead",
       subtitle = "Mean-reverting toward long-run unconditional volatility",
       x = "Days Ahead", y = "Annualised Volatility", color = NULL) +
  theme_minimal(base_size = 11) +
  theme(plot.title = element_text(face = "bold"))

#  Price Comparison — GARCH vs Hist vs IV (all maturities) ---
price_long <- all_data %>%
  select(Maturity, Strike, Price_GARCH, Price_Hist, Price_IV) %>%
  pivot_longer(cols = c(Price_GARCH, Price_Hist, Price_IV),
               names_to = "Method", values_to = "Price") %>%
  mutate(Method = recode(Method,
                         "Price_GARCH" = "GARCH",
                         "Price_Hist"  = "Historical",
                         "Price_IV"    = "Implied Vol"
  ))

p_compare <- ggplot(price_long, aes(x = Strike, y = Price, color = Method)) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 1.8) +
  facet_wrap(~Maturity, scales = "free_y") +
  scale_color_manual(values = c(
    "GARCH"        = "#27AE60",
    "Historical"   = "#1F4E79",
    "Implied Vol"  = "#E74C3C"
  )) +
  geom_vline(xintercept = S, linetype = "dashed",
             color = "grey50", linewidth = 0.6) +
  annotate("text", x = S, y = -Inf, vjust = -0.5,
           label = "Spot", size = 3, color = "grey40") +
  labs(title = "Option Prices: GARCH vs Historical Vol vs Implied Vol",
       subtitle = "Dashed line = current spot price",
       x = "Strike (€)", y = "Call Price (€)", color = "Vol Method") +
  theme_minimal(base_size = 11) +
  theme(plot.title = element_text(face = "bold"))

# Plot 4: Vol Method Comparison by Maturity 
vol_comp <- data.frame(
  Maturity = c("30d", "60d", "90d"),
  GARCH    = unlist(garch_vol),
  Hist     = rep(hist_vol_annual, 3)
) %>%
  pivot_longer(cols = c(GARCH, Hist),
               names_to = "Method", values_to = "Vol")

p_vol_comp <- ggplot(vol_comp, aes(x = Maturity, y = Vol, fill = Method)) +
  geom_col(position = "dodge", width = 0.5) +
  scale_fill_manual(values = c("GARCH" = "#27AE60", "Hist" = "#1F4E79")) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
  labs(title = "GARCH vs Historical Vol by Maturity",
       subtitle = "GARCH vol changes with horizon; Historical is flat",
       x = "Maturity", y = "Annualised Volatility", fill = "Method") +
  theme_minimal(base_size = 11) +
  theme(plot.title = element_text(face = "bold"))

#  Plot 5: Pricing Difference — GARCH minus Historical
diff_df <- all_data %>%
  mutate(Price_Diff = Price_GARCH - Price_Hist)

p_diff <- ggplot(diff_df, aes(x = Strike, y = Price_Diff, color = Maturity)) +
  geom_line(linewidth = 1) +
  geom_point(size = 2) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "grey50") +
  scale_color_manual(values = c("30d" = "#1F4E79",
                                "60d" = "#2E86C1",
                                "90d" = "#85C1E9")) +
  geom_vline(xintercept = S, linetype = "dashed",
             color = "grey50", linewidth = 0.6) +
  labs(title = "Pricing Difference: GARCH minus Historical Vol",
       subtitle = "Positive = GARCH prices higher; Negative = Historical prices higher",
       x = "Strike (€)", y = "Price Difference (€)", color = "Maturity") +
  theme_minimal(base_size = 11) +
  theme(plot.title = element_text(face = "bold"))

#  Plot 6: Greeks across strikes (GARCH vol, 30d) 
greeks_30 <- all_data %>%
  filter(Days == 30) %>%
  select(Strike, Delta, Gamma, Vega, Theta) %>%
  pivot_longer(cols = c(Delta, Gamma, Vega, Theta),
               names_to = "Greek", values_to = "Value")

p_greeks <- ggplot(greeks_30, aes(x = Strike, y = Value, color = Greek)) +
  geom_line(linewidth = 1) +
  facet_wrap(~Greek, scales = "free_y", nrow = 2) +
  geom_vline(xintercept = S, linetype = "dashed",
             color = "grey50", linewidth = 0.6) +
  scale_color_manual(values = c(
    "Delta" = "#1F4E79", "Gamma" = "#E74C3C",
    "Vega"  = "#27AE60", "Theta" = "#F39C12"
  )) +
  labs(title = "Greeks across Strikes — GARCH Vol (30d)",
       subtitle = "Dashed = spot price",
       x = "Strike (€)", y = "Greek Value") +
  theme_minimal(base_size = 11) +
  theme(plot.title  = element_text(face = "bold"),
        legend.position = "none")


# SECTION 6: RENDER ALL PLOTS

print(p_price)
print(p_rollvol)
print(p_garch_fc)
print(p_compare)
print(p_vol_comp)
print(p_diff)
print(p_greeks)
                  
# SECTION 7: SUMMARY COMPARISON TABLE
cat("FINAL COMPARISON: GARCH vs Historical Vol vs IV\n")

summary_tbl <- all_data %>%
  filter(Strike %in% strikes[c(3, 5, 6, 7, 9)]) %>%   # OTM, near, ATM, near, ITM
  select(Maturity, Strike, Moneyness,
         GARCH_Vol, Hist_Vol, IV,
         Price_GARCH, Price_Hist, Price_IV, Price_MC) %>%
  mutate(
    GARCH_vs_Hist = round(Price_GARCH - Price_Hist, 4),
    GARCH_vs_IV   = round(Price_GARCH - Price_IV,   4)
  )

print(summary_tbl)

cat("\n=== Vol Summary ===\n")
cat("Historical Vol (1yr annualised) :", round(hist_vol_annual * 100, 2), "%\n")
cat("GARCH Forecast — 30d            :", round(garch_vol[["30"]] * 100, 2), "%\n")
cat("GARCH Forecast — 60d            :", round(garch_vol[["60"]] * 100, 2), "%\n")
cat("GARCH Forecast — 90d            :", round(garch_vol[["90"]] * 100, 2), "%\n")
cat("GARCH Long-Run (unconditional)  :", round(uncond_vol * 100, 2), "%\n")
cat("GARCH Persistence (α+β)         :", round(persistence, 4), "\n")

cat("\n=== How to interpret the comparison ===\n")
cat("If GARCH_Vol > Hist_Vol : market has been getting MORE volatile recently\n")
cat("If GARCH_Vol < Hist_Vol : market has been CALMING DOWN recently\n")
cat("If GARCH_Vol ≈ IV       : GARCH forecast aligns with market expectations\n")
cat("If GARCH_Vol ≠ IV       : market pricing in different risk to what GARCH predicts\n")
