# Credit Risk Scorecard (German Credit Dataset)

This project builds a simple credit risk scorecard to estimate the probability of default and convert it into an interpretable credit score.

Two versions of the model are implemented:

* **Baseline model** using all variables after WOE transformation
* **Refined model** using Information Value (IV) for variable selection

---

## Approach

The workflow follows a standard credit risk pipeline:

* Data preprocessing and train-test split
* WOE (Weight of Evidence) transformation
* Logistic regression modeling
* Model evaluation using ROC, AUC, and KS
* Scorecard construction and score generation

---

## Models

**1. creditriskGerman.R**
Uses all variables after WOE transformation. Acts as a baseline model.

**2. withIV.R**
Selects variables with IV > 0.02 before modeling, leading to a cleaner and more interpretable model.

---

## Output

* ROC curve and AUC for model performance
* KS statistic for separation power
* Credit score distribution
* Simple decision rule:

  * Approve if score > 600
  * Reject otherwise

---

## How to Run

1. Place `GermanCredit.csv` in your working directory
2. Update file path if needed
3. Run either script in R

Required packages: `tidyverse`, `caret`, `pROC`, `scorecard`

---

## Notes

This project focuses on building a practical and interpretable credit scoring pipeline using logistic regression and scorecards.
