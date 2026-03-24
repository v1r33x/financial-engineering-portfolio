# asml options pricing engine
# garch vs historical vol vs implied vol

packages <- c("RQuantLib","quantmod","rugarch","ggplot2",
              "dplyr","tidyr","gridExtra","zoo")

installed <- packages %in% rownames(installed.packages())

if(any(!installed)){
  install.packages(packages[!installed])
}

library(RQuantLib)
library(quantmod)
library(rugarch)
library(ggplot2)
library(dplyr)
library(tidyr)
library(gridExtra)
library(zoo)

set.seed(42)


# fetch data

cat("fetching ASML data\n")

getSymbols("ASML.AS", src = "yahoo",
           from = Sys.Date() - 365,
           to   = Sys.Date(),
           auto.assign = TRUE)

prices  <- Cl(ASML.AS)
prices  <- na.omit(prices)
returns <- na.omit(diff(log(prices)))

S <- as.numeric(tail(prices, 1))
r <- 0.035

cat("spot:", round(S, 2), "\n")
cat("obs :", nrow(returns), "\n\n")


# volatility

hist_vol_annual <- as.numeric(sd(returns)) * sqrt(252)

roll_vol <- rollapply(returns, width = 30,
                      FUN = function(x) sd(x) * sqrt(252),
                      align = "right", fill = NA)

cat("hist vol:", round(hist_vol_annual, 4), "\n")


spec <- ugarchspec(
  variance.model = list(model = "sGARCH", garchOrder = c(1,1)),
  mean.model     = list(armaOrder = c(0,0), include.mean = TRUE),
  distribution.model = "norm"
)

fit <- ugarchfit(spec = spec, data = returns, solver = "hybrid")

print(round(coef(fit), 6))

alpha <- coef(fit)["alpha1"]
beta  <- coef(fit)["beta1"]
omega <- coef(fit)["omega"]

persistence <- alpha + beta

cat("persistence:", round(persistence, 4), "\n")

uncond_vol <- sqrt(omega / (1 - persistence)) * sqrt(252)
cat("long-run vol:", round(uncond_vol, 4), "\n")


fc_90 <- ugarchforecast(fit, n.ahead = 90)
sigma_daily <- as.numeric(sigma(fc_90))

garch_vol <- list(
  "30" = mean(sigma_daily[1:30]) * sqrt(252),
  "60" = mean(sigma_daily[1:60]) * sqrt(252),
  "90" = mean(sigma_daily[1:90]) * sqrt(252)
)

cat("garch vols:", round(garch_vol[["30"]],4),
    round(garch_vol[["60"]],4),
    round(garch_vol[["90"]],4), "\n")


# pricing functions

bs_price <- function(S, K, T, r, sigma){
  as.numeric(
    tryCatch(
      EuropeanOption("call", S, K, 0, r, T, sigma)$value,
      error = function(e) NA_real_
    )
  )
}

implied_vol <- function(price, S, K, T, r, init_vol = 0.2){
  as.numeric(
    tryCatch(
      EuropeanOptionImpliedVolatility("call", price, S, K, 0, r, T, init_vol),
      error = function(e) NA_real_
    )
  )
}

mc_price <- function(S, K, T, r, sigma, n_sim = 100000){
  Z  <- rnorm(n_sim)
  ST <- S * exp((r - 0.5 * sigma^2) * T + sigma * sqrt(T) * Z)
  exp(-r * T) * mean(pmax(ST - K, 0))
}

get_greeks <- function(S, K, T, r, sigma){

  opt <- tryCatch(
    EuropeanOption("call", S, K, 0, r, T, sigma),
    error = function(e) NULL
  )

  if(is.null(opt)){
    return(list(delta=NA,gamma=NA,vega=NA,theta=NA))
  }

  list(
    delta = as.numeric(opt$delta),
    gamma = as.numeric(opt$gamma),
    vega  = as.numeric(opt$vega),
    theta = as.numeric(opt$theta)
  )
}


# build surface

strikes    <- round(seq(S * 0.80, S * 1.20, length.out = 11), 0)
maturities <- c(30, 60, 90)

cat("strikes:", strikes, "\n")

all_data <- do.call(rbind, lapply(maturities, function(days){

  T_i     <- days / 365
  garch_s <- garch_vol[[as.character(days)]]
  hist_s  <- hist_vol_annual

  do.call(rbind, lapply(strikes, function(K){

    price_garch <- bs_price(S, K, T_i, r, garch_s)
    price_hist  <- bs_price(S, K, T_i, r, hist_s)

    iv_val <- implied_vol(price_garch + rnorm(1, 0, 0.3),
                          S, K, T_i, r)

    price_iv <- if(!is.na(iv_val)){
      bs_price(S, K, T_i, r, iv_val)
    } else {
      NA_real_
    }

    price_mc <- mc_price(S, K, T_i, r, garch_s)

    g <- get_greeks(S, K, T_i, r, garch_s)

    data.frame(
      Maturity    = paste0(days,"d"),
      Days        = days,
      Strike      = K,
      Moneyness   = round(K / S, 3),
      GARCH_Vol   = round(garch_s,4),
      Hist_Vol    = round(hist_s,4),
      IV          = round(iv_val,4),
      Price_GARCH = round(price_garch,4),
      Price_Hist  = round(price_hist,4),
      Price_IV    = round(price_iv,4),
      Price_MC    = round(price_mc,4),
      Delta       = round(g$delta,4),
      Gamma       = round(g$gamma,4),
      Vega        = round(g$vega,4),
      Theta       = round(g$theta,4)
    )
  }))
}))

print(all_data %>% select(Maturity, Strike, Moneyness,
                         GARCH_Vol, Hist_Vol, IV,
                         Price_GARCH, Price_Hist, Price_IV, Price_MC))


# plots

prices_df <- data.frame(Date=index(prices), Price=as.numeric(prices))

roll_df <- data.frame(Date=index(roll_vol),
                      RollVol=as.numeric(roll_vol)) %>%
  filter(!is.na(RollVol))

p_price <- ggplot(prices_df, aes(Date, Price)) +
  geom_line(color="#1F4E79", linewidth=0.8) +
  labs(title="ASML price", y="€") +
  theme_minimal()

p_rollvol <- ggplot(roll_df, aes(Date, RollVol)) +
  geom_line(color="#E74C3C", linewidth=0.8) +
  geom_hline(yintercept=hist_vol_annual, linetype="dashed",
             color="#1F4E79") +
  geom_hline(yintercept=garch_vol[["30"]], linetype="dashed",
             color="#27AE60") +
  labs(title="rolling vol", y="annual vol") +
  theme_minimal()


fc_df <- data.frame(
  Day = 1:90,
  GARCH = sigma_daily * sqrt(252),
  Hist  = rep(hist_vol_annual, 90)
)

p_garch_fc <- ggplot(fc_df, aes(Day)) +
  geom_line(aes(y=GARCH,color="GARCH"), linewidth=1) +
  geom_line(aes(y=Hist,color="Hist"), linetype="dashed") +
  geom_hline(yintercept=uncond_vol, linetype="dotted") +
  scale_color_manual(values=c("GARCH"="#27AE60","Hist"="#1F4E79")) +
  labs(title="garch forecast", y="vol") +
  theme_minimal()


price_long <- all_data %>%
  select(Maturity, Strike, Price_GARCH, Price_Hist, Price_IV) %>%
  pivot_longer(cols=c(Price_GARCH,Price_Hist,Price_IV),
               names_to="Method", values_to="Price") %>%
  mutate(Method = recode(Method,
                         "Price_GARCH"="GARCH",
                         "Price_Hist"="Historical",
                         "Price_IV"="IV"))

p_compare <- ggplot(price_long, aes(Strike, Price, color=Method)) +
  geom_line() +
  geom_point() +
  facet_wrap(~Maturity, scales="free_y") +
  geom_vline(xintercept=S, linetype="dashed") +
  theme_minimal()


vol_comp <- data.frame(
  Maturity=c("30d","60d","90d"),
  GARCH=unlist(garch_vol),
  Hist=rep(hist_vol_annual,3)
) %>%
  pivot_longer(cols=c(GARCH,Hist),
               names_to="Method", values_to="Vol")

p_vol_comp <- ggplot(vol_comp, aes(Maturity, Vol, fill=Method)) +
  geom_col(position="dodge") +
  theme_minimal()


diff_df <- all_data %>%
  mutate(Price_Diff = Price_GARCH - Price_Hist)

p_diff <- ggplot(diff_df, aes(Strike, Price_Diff, color=Maturity)) +
  geom_line() +
  geom_hline(yintercept=0, linetype="dashed") +
  theme_minimal()


greeks_30 <- all_data %>%
  filter(Days==30) %>%
  select(Strike, Delta, Gamma, Vega, Theta) %>%
  pivot_longer(cols=c(Delta,Gamma,Vega,Theta),
               names_to="Greek", values_to="Value")

p_greeks <- ggplot(greeks_30, aes(Strike, Value, color=Greek)) +
  geom_line() +
  facet_wrap(~Greek, scales="free_y") +
  geom_vline(xintercept=S, linetype="dashed") +
  theme_minimal()


print(p_price)
print(p_rollvol)
print(p_garch_fc)
print(p_compare)
print(p_vol_comp)
print(p_diff)
print(p_greeks)


# summary

cat("comparison\n")

summary_tbl <- all_data %>%
  filter(Strike %in% strikes[c(3,5,6,7,9)]) %>%
  select(Maturity, Strike, Moneyness,
         GARCH_Vol, Hist_Vol, IV,
         Price_GARCH, Price_Hist, Price_IV, Price_MC) %>%
  mutate(
    GARCH_vs_Hist = round(Price_GARCH - Price_Hist, 4),
    GARCH_vs_IV   = round(Price_GARCH - Price_IV, 4)
  )

print(summary_tbl)

cat("hist:", round(hist_vol_annual*100,2), "%\n")
cat("garch 30:", round(garch_vol[["30"]]*100,2), "%\n")
cat("garch 60:", round(garch_vol[["60"]]*100,2), "%\n")
cat("garch 90:", round(garch_vol[["90"]]*100,2), "%\n")
cat("long-run:", round(uncond_vol*100,2), "%\n")
cat("persistence:", round(persistence,4), "\n")
