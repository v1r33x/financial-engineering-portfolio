# install packages if needed
packages <- c("tidyverse","caret","pROC","scorecard")
installed <- packages %in% rownames(installed.packages())

if(any(!installed)){
  install.packages(packages[!installed])
}

library(tidyverse)
library(caret)
library(pROC)
library(scorecard)


# load data
data <- read.csv("C:/Users/rahtu/OneDrive/Desktop/GermanCredit.csv")

# create default variable (1 = default)
data$default <- ifelse(data$credit_risk == 0, 1, 0)
data$credit_risk <- NULL

# convert character variables to factors
data[] <- lapply(data, function(x){
  if(is.character(x)) as.factor(x) else x
})


# train/test split
set.seed(123)
train_index <- createDataPartition(data$default, p = 0.7, list = FALSE)

train <- data[train_index, ]
test  <- data[-train_index, ]


# woe binning
bins <- woebin(train, y = "default")

train_woe <- woebin_ply(train, bins)
test_woe  <- woebin_ply(test, bins)

train_woe <- as.data.frame(train_woe)
test_woe  <- as.data.frame(test_woe)


# information value
iv_values <- iv(train_woe, "default")
print(iv_values)

selected_vars <- iv_values %>%
  filter(info_value > 0.02) %>%
  pull(variable)

print(selected_vars)


# modeling datasets
train_model <- train_woe[, selected_vars]
test_model  <- test_woe[, selected_vars]

train_model$default <- train_woe$default
test_model$default  <- test_woe$default


# logistic regression
model <- glm(default ~ ., data = train_model, family = binomial)
summary(model)


# predictions
pred <- predict(model, test_model, type = "response")


# roc / auc
roc_obj <- roc(test_model$default, pred)
print(paste("AUC:", auc(roc_obj)))

plot(roc_obj, col = "blue", main = "ROC Curve")


# ks statistic
perf <- perf_eva(pred, test_model$default, show_plot = TRUE)


# scorecard
card <- scorecard(bins, model)
print(card)


# borrower scores
test_scores <- scorecard_ply(test, card)
head(test_scores)


# score distribution
hist(test_scores$score,
     breaks = 30,
     main = "Credit Score Distribution",
     xlab = "Score")


# decision rule
test_scores$decision <- ifelse(test_scores$score > 600, "Approve", "Reject")
table(test_scores$decision)