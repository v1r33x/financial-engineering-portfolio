


# Load required packages

required_packages <- c("tidyverse", "caret", "pROC", "scorecard")

installed <- required_packages %in% installed.packages()

if (any(!installed)) {
  install.packages(required_packages[!installed])
}

library(tidyverse)
library(caret)
library(pROC)
library(scorecard)



#  Load and prepare data

data <- read.csv("C:/Users/rahtu/OneDrive/Desktop/GermanCredit.csv")

# Define target variable:
# original: 1 = good, 0 = bad
# we convert to: 1 = default (bad), 0 = non-default (good)
data$default <- ifelse(data$credit_risk == 0, 1, 0)

# remove original column
data$credit_risk <- NULL

# convert categorical variables into factors
data[] <- lapply(data, function(x) {
  if (is.character(x)) as.factor(x) else x
})



# Train-test split

set.seed(123)

train_index <- createDataPartition(data$default, p = 0.7, list = FALSE)

train <- data[train_index, ]
test  <- data[-train_index, ]



#  WOE binning

bins <- woebin(train, y = "default")

# visualize binning structure
woebin_plot(bins)



#  Transform data using WOE

train_woe <- woebin_ply(train, bins)
test_woe  <- woebin_ply(test, bins)



# Logistic regression model

model <- glm(default ~ ., 
             data = train_woe, 
             family = binomial)

summary(model)



#  Model evaluation

pred <- predict(model, test_woe, type = "response")

# ROC and AUC
roc_obj <- roc(test_woe$default, pred)
print(paste("AUC:", auc(roc_obj)))

plot(roc_obj, col = "blue", main = "ROC Curve")



#  KS statistic

perf <- perf_eva(test_woe$default, pred, show_plot = TRUE)



# Build scorecard

card <- scorecard(bins, model)
print(card)



#  Generate scores

test_scores <- scorecard_ply(test, card)

head(test_scores)



# Score distribution

hist(test_scores$score,
     breaks = 30,
     main = "Credit Score Distribution",
     xlab = "Score")



#Decision rule
test_scores$decision <- ifelse(test_scores$score > 600,
                               "Approve",
                               "Reject")

table(test_scores$decision)