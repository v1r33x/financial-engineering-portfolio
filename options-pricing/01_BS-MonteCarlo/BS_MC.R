# options pricing engine (Black-Scholes, IV, Monte Carlo, Greeks)

packages <- c("RQuantLib", "ggplot2", "dplyr", "tidyr", "gridExtra")
installed <- packages %in% rownames(installed.packages())

if(any(!installed)){
  install.packages(packages[!installed])
}

library(RQuantLib)
library(ggplot2)
library(dplyr)
library(tidyr)
library(gridExtra)

set.seed(42)


S        <- 252.82
r        <- 0.03
true_vol <- 0.25

strikes    <- seq(200, 300, by = 5)
maturities <- c(30, 60, 90)   # days


# black-scholes price
bs_price <- function(S, K, T, r, sigma){
  as.numeric(
    tryCatch(
      EuropeanOption("call", S, K, 0, r, T, sigma)$value,
      error = function(e) NA_real_
    )
  )
}

# implied volatility
implied_vol <- function(price, S, K, T, r, init_vol = 0.2){
  as.numeric(
    tryCatch(
      EuropeanOptionImpliedVolatility("call", price, S, K, 0, r, T, init_vol),
      error = function(e) NA_real_
    )
  )
}

# monte carlo pricing
mc_price <- function(S, K, T, r, sigma, n_sim = 100000){
  Z  <- rnorm(n_sim)
  ST <- S * exp((r - 0.5 * sigma^2) * T + sigma * sqrt(T) * Z)
  exp(-r * T) * mean(pmax(ST - K, 0))
}

# greeks
get_greeks <- function(S, K, T, r, sigma){

  opt <- tryCatch(
    EuropeanOption("call", S, K, 0, r, T, sigma),
    error = function(e) NULL
  )

  if(is.null(opt)){
    return(list(delta=NA, gamma=NA, vega=NA, theta=NA, rho=NA))
  }

  list(
    delta = as.numeric(opt$delta),
    gamma = as.numeric(opt$gamma),
    vega  = as.numeric(opt$vega),
    theta = as.numeric(opt$theta),
    rho   = as.numeric(opt$rho)
  )
}

# monte carlo convergence
mc_convergence <- function(S, K, T, r, sigma, steps = 50){

  sim_sizes <- as.integer(seq(1000, 100000, length.out = steps))

  prices <- sapply(sim_sizes, function(n){
    mc_price(S, K, T, r, sigma, n)
  })

  data.frame(n_sim = sim_sizes, MC_Price = prices)
}


# build surface data

surface_data <- do.call(rbind, lapply(maturities, function(days){

  T_i <- days / 365

  # simulate market prices
  market_px <- sapply(strikes, function(K){
    p <- bs_price(S, K, T_i, r, true_vol)
    max(p + rnorm(1, 0, 0.3), 0.01)
  })

  # implied vols
  ivs <- sapply(seq_along(strikes), function(i){
    implied_vol(market_px[i], S, strikes[i], T_i, r)
  })

  # BS + MC using IV
  bs_px <- sapply(seq_along(strikes), function(i){
    if(!is.na(ivs[i])) bs_price(S, strikes[i], T_i, r, ivs[i]) else NA_real_
  })

  mc_px <- sapply(seq_along(strikes), function(i){
    if(!is.na(ivs[i])) mc_price(S, strikes[i], T_i, r, ivs[i]) else NA_real_
  })

  # greeks
  greeks_list <- lapply(seq_along(strikes), function(i){
    if(!is.na(ivs[i])){
      get_greeks(S, strikes[i], T_i, r, ivs[i])
    } else {
      list(delta=NA, gamma=NA, vega=NA, theta=NA, rho=NA)
    }
  })

  data.frame(
    Maturity = paste0(days, "d"),
    Days     = days,
    Strike   = strikes,
    Market   = as.numeric(market_px),
    IV       = as.numeric(ivs),
    BS       = as.numeric(bs_px),
    MC       = as.numeric(mc_px),
    Delta    = sapply(greeks_list, `[[`, "delta"),
    Gamma    = sapply(greeks_list, `[[`, "gamma"),
    Vega     = sapply(greeks_list, `[[`, "vega"),
    Theta    = sapply(greeks_list, `[[`, "theta"),
    Rho      = sapply(greeks_list, `[[`, "rho")
  )

})) %>% filter(!is.na(IV))


# 30d slice
df_30 <- surface_data %>% filter(Days == 30)

cat("surface preview\n")
print(head(surface_data, 10))


# implied vol surface

p1 <- ggplot(surface_data, aes(x = Strike, y = IV, color = Maturity, group = Maturity)) +
  geom_line(linewidth = 1) +
  geom_point(size = 2) +
  scale_color_manual(values = c("30d" = "#1F4E79", "60d" = "#2E86C1", "90d" = "#85C1E9")) +
  labs(
    title = "Implied Volatility Surface",
    subtitle = "Call options across strikes and maturities",
    x = "Strike",
    y = "Implied Volatility",
    color = "Maturity"
  ) +
  theme_minimal(base_size = 12) +
  theme(plot.title = element_text(face = "bold"))


# market vs bs vs mc (30d)

comp_long <- df_30 %>%
  select(Strike, Market, BS, MC) %>%
  pivot_longer(cols = c(Market, BS, MC), names_to = "Method", values_to = "Price")

p2 <- ggplot(comp_long, aes(x = Strike, y = Price, color = Method)) +
  geom_line(linewidth = 1) +
  geom_point(size = 1.5) +
  scale_color_manual(values = c("Market" = "#1F4E79", "BS" = "#E74C3C", "MC" = "#27AE60")) +
  labs(
    title = "Market vs Black-Scholes vs Monte Carlo (30d)",
    subtitle = "Prices using implied vol",
    x = "Strike",
    y = "Option Price",
    color = "Method"
  ) +
  theme_minimal(base_size = 12) +
  theme(plot.title = element_text(face = "bold"))


# greeks (30d)

greeks_long <- df_30 %>%
  select(Strike, Delta, Gamma, Vega, Theta) %>%
  pivot_longer(cols = c(Delta, Gamma, Vega, Theta), names_to = "Greek", values_to = "Value")

p3 <- ggplot(greeks_long, aes(x = Strike, y = Value, color = Greek)) +
  geom_line(linewidth = 1) +
  facet_wrap(~Greek, scales = "free_y", nrow = 2) +
  scale_color_manual(values = c(
    "Delta" = "#1F4E79",
    "Gamma" = "#E74C3C",
    "Vega"  = "#27AE60",
    "Theta" = "#F39C12"
  )) +
  labs(
    title = "Greeks across strikes (30d)",
    x = "Strike",
    y = "Value"
  ) +
  theme_minimal(base_size = 12) +
  theme(plot.title = element_text(face = "bold"), legend.position = "none")


# monte carlo convergence (atm, 30d)

atm_strike <- strikes[which.min(abs(strikes - S))]
atm_iv_30  <- df_30 %>% filter(Strike == atm_strike) %>% pull(IV)
bs_atm_30  <- df_30 %>% filter(Strike == atm_strike) %>% pull(BS)

conv_df <- mc_convergence(S, atm_strike, 30/365, r, atm_iv_30)

p4 <- ggplot(conv_df, aes(x = n_sim, y = MC_Price)) +
  geom_line(color = "#27AE60", linewidth = 1) +
  geom_hline(yintercept = bs_atm_30, color = "#E74C3C", linetype = "dashed", linewidth = 0.8) +
  annotate(
    "text",
    x = max(conv_df$n_sim) * 0.55,
    y = bs_atm_30 + (max(conv_df$MC_Price) - min(conv_df$MC_Price)) * 0.08,
    label = paste0("BS Price: ", round(bs_atm_30, 4)),
    color = "#E74C3C",
    size = 3.5
  ) +
  labs(
    title = paste0("MC convergence (ATM, K=", atm_strike, ", 30d)"),
    x = "Simulations",
    y = "MC Price"
  ) +
  theme_minimal(base_size = 12) +
  theme(plot.title = element_text(face = "bold"))


# pricing error (30d)

df_30_err <- df_30 %>%
  mutate(BS_err = abs(BS - Market), MC_err = abs(MC - Market)) %>%
  select(Strike, BS_err, MC_err) %>%
  pivot_longer(cols = c(BS_err, MC_err), names_to = "Method", values_to = "AbsError") %>%
  mutate(Method = recode(Method, "BS_err" = "Black-Scholes", "MC_err" = "Monte Carlo"))

p5 <- ggplot(df_30_err, aes(x = Strike, y = AbsError, fill = Method)) +
  geom_col(position = "dodge") +
  scale_fill_manual(values = c("Black-Scholes" = "#E74C3C", "Monte Carlo" = "#27AE60")) +
  labs(
    title = "Absolute pricing error (30d)",
    x = "Strike",
    y = "Error"
  ) +
  theme_minimal(base_size = 12) +
  theme(plot.title = element_text(face = "bold"))


print(p1)
print(p2)
print(p3)
print(p4)
print(p5)


# summary

cat("\ngreeks summary (30d)\n")

df_30 %>%
  filter(Strike %in% c(230, 245, 250, 255, 260, 270, 280)) %>%
  select(Strike, IV, BS, MC, Delta, Gamma, Vega, Theta) %>%
  mutate(across(where(is.numeric), ~round(.x, 4))) %>%
  print()

cat("\nmonte carlo convergence summary\n")
cat("ATM Strike        :", atm_strike, "\n")
cat("BS ATM Price      :", round(bs_atm_30, 4), "\n")
cat("MC ATM (100k sims):", round(tail(conv_df$MC_Price, 1), 4), "\n")
cat("Convergence error :", round(abs(tail(conv_df$MC_Price, 1) - bs_atm_30), 5), "\n")
