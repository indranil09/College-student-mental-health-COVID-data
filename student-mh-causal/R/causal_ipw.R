###############################################################################
# Propensity score weighted estimates of the effects of academic, psychological,
# and social factors on college student mental health during early COVID-19.
#
# Companion code for:
#   Shearer E, Paez Carrion N, Jackson J, Amona E, Qian Y, Chan D, Sahoo I.
#   "A causal analysis of academic, psychological, and social influences on
#    college student mental health during the COVID-19 pandemic."
#   PLOS Mental Health (under revision, PMEN-D-26-00242).
#
# Pipeline, run separately for every subgroup x treatment:
#   1. covariates = all measured variables except the outcome (mh_scale), the
#      self-reported COVID-19 effect on mental health (covid_mh), and the
#      variable the treatment is built from
#   2. propensity scores from XGBoost, boosting rounds chosen by 5-fold CV
#   3. unstabilized, untruncated ATE weights  w = D/p + (1 - D)/(1 - p)
#   4. diagnostics: SMD before/after weighting, weight range, effective sample
#      size, overlap plots
#   5. weighted least squares of mh_scale on the treatment with HC2 standard
#      errors (estimatr::lm_robust); 90% confidence intervals (alpha = 0.10)
#   6. Benjamini-Hochberg adjustment across all estimates
#
# Run from the student-mh-causal/ folder:   Rscript R/causal_ipw.R
# Required packages: xgboost, estimatr  (diagnostics and plots use base R)
# Outputs (in output/):
#   results.csv        one row per subgroup x treatment (Tables 3 to 7, S1, S2)
#   balance.csv        SMD of every covariate before and after weighting (S1 Data)
#   overlap_plots.pdf  propensity score distributions by treatment arm (Fig S1)
#   session_info.txt   R and package versions
#
# Each row of results.csv also contains `dr_estimate`, a doubly robust variant
# (same weights, confounders added to the outcome model). It is provided for
# reference only; the paper reports `estimate`.
###############################################################################

library(estimatr)

# ----------------------------------------------------------------------------
# 0. Settings
# ----------------------------------------------------------------------------
data_file  <- "data/numeric_GPA3_0_first.csv"
out_dir    <- "output"
seed       <- 2024
alpha      <- 0.10          # 90% confidence intervals, as in the paper
ps_method  <- "xgb"         # "xgb" (boosted trees) or "logit" (main-effects glm)
smd_cutoff <- 0.1           # conventional balance threshold
n_boot     <- 0             # set to e.g. 500 for bootstrap CIs (slow with xgb)

xgb_params <- list(
  objective        = "binary:logistic",
  eval_metric      = "logloss",
  eta              = 0.05,   # learning rate
  max_depth        = 2,      # shallow trees: small samples
  min_child_weight = 5,
  subsample        = 0.8,
  colsample_bytree = 0.8,
  nthread          = 1       # reproducible
)
# Reduced confounder set, used only (a) by the alternative ps_method = "logit"
# (a glm on all ~50 survey columns separates completely) and (b) in the doubly
# robust outcome model reported as `dr_estimate`. The XGBoost propensity model
# used in the paper takes all measured covariates (see build_covariates).
confounders <- c("age", "gender", "race", "first_gen", "stem_notstem", "hours",
                      "has_mother", "has_father", "prime_count", "edu.i_count",
                      "max.emohelp", "ss_family", "ss_friend", "ss_sigother",
                      "acpers", "ptsd_score", "trauma_sum", "covid_iso", "gpa_thresh3_0")

xgb_max_rounds <- 1000
xgb_nfold      <- 5
xgb_early_stop <- 25

dir.create(out_dir, showWarnings = FALSE)

# ----------------------------------------------------------------------------
# 1. Data
# ----------------------------------------------------------------------------
raw <- read.csv(data_file)
raw$age[raw$age == 0] <- NA              # 0 means missing, not age zero
cat("Rows:", nrow(raw), " | age missing:", sum(is.na(raw$age)), "\n")

# Variables never used as confounders:
#   mh_scale  = the outcome
#   covid_mh  = "COVID is affecting my mental health" (a proxy for the outcome)
never_covariates <- c("record_id", "mh_scale", "covid_mh")

# ----------------------------------------------------------------------------
# 2. Treatment definitions (1 = treated). `source` lists the raw columns the
#    treatment is built from; they are removed from the propensity model.
#    Medians for acpers (4.5) and trauma_sum (10) are full-sample medians.
#    trauma_sum is scored so that HIGHER values mean FEWER traumatic experiences.
# ----------------------------------------------------------------------------
treatments <- list(
  gpa       = list(label  = "GPA 3.0 or below",
                   make   = function(d) d$gpa_thresh3_0,
                   source = "gpa_thresh3_0"),
  ptsd      = list(label  = "PTSD score 33 or higher",
                   make   = function(d) as.integer(d$ptsd_score >= 33),
                   source = "ptsd_score"),
  iso       = list(label  = "COVID isolation above 7",
                   make   = function(d) as.integer(d$covid_iso > 7),
                   source = "covid_iso"),
  edu       = list(label  = "Three or more intense educational helpers",
                   make   = function(d) as.integer(d$edu.i_count >= 3),
                   source = "edu.i_count"),
  emo_max   = list(label  = "Maximum emotional help 9 or higher",
                   make   = function(d) as.integer(d$max.emohelp >= 9),
                   source = "max.emohelp"),
  acpers    = list(label  = "Academic perseverance above median",
                   make   = function(d) as.integer(d$acpers > median(raw$acpers)),
                   source = "acpers"),
  trauma    = list(label  = "Trauma score above median (fewer traumatic events)",
                   make   = function(d) as.integer(d$trauma_sum > median(raw$trauma_sum)),
                   source = "trauma_sum"),
  gender    = list(label  = "Not a cisgender woman",
                   make   = function(d) as.integer(d$gender != 0),
                   source = "gender")
)

# ----------------------------------------------------------------------------
# 3. Analysis plan: subgroups and the treatments examined in each
#    (same structure as Tables 3 to 7). gender: 0 = cis woman, 1 = cis man,
#    2 = gender minority. race: 0 = White, 1 = Black/Latinx/Other, 2 = Asian.
# ----------------------------------------------------------------------------
four <- c("gpa", "ptsd", "iso")   # primary exposures, examined in every non-PTSD stratum
plan <- list(
  list(group = "Full sample",           rows = function(d) rep(TRUE, nrow(d)),               trt = c(four, "edu")),
  list(group = "High PTSD (>=33)",      rows = function(d) d$ptsd_score >= 33,               trt = c("gpa", "iso", "acpers", "gender", "trauma")),
  list(group = "Low PTSD (<33)",        rows = function(d) d$ptsd_score <  33,               trt = c("gpa", "iso", "acpers", "gender", "trauma")),
  list(group = "Cisgender women",       rows = function(d) d$gender == 0,                    trt = c(four, "edu")),
  list(group = "Cisgender men",         rows = function(d) d$gender == 1,                    trt = c(four, "edu")),
  list(group = "White",                 rows = function(d) d$race == 0,                      trt = c(four, "edu")),
  list(group = "Asian/Asian-American",  rows = function(d) d$race == 2,                      trt = c(four, "edu")),
  list(group = "Other racial identity", rows = function(d) d$race == 1,                      trt = c(four, "edu")),
  list(group = "Ages 18-20",            rows = function(d) !is.na(d$age) & d$age <= 20,      trt = c(four, "emo_max")),
  list(group = "Ages 21-24",            rows = function(d) !is.na(d$age) & d$age %in% 21:24, trt = c(four, "emo_max")),
  list(group = "Ages 25+",              rows = function(d) !is.na(d$age) & d$age >= 25,      trt = c(four, "emo_max"))
)

# ----------------------------------------------------------------------------
# 4. Helper functions
# ----------------------------------------------------------------------------

# Covariate matrix for one analysis: everything except the outcome, its proxy,
# the treatment's source column(s), and columns that are constant in the subgroup.
build_covariates <- function(d, trt_name) {
  drop <- c(never_covariates, treatments[[trt_name]]$source)
  X <- d[, setdiff(names(d), drop), drop = FALSE]
  keep <- vapply(X, function(v) length(unique(v[!is.na(v)])) > 1, logical(1))
  X[, keep, drop = FALSE]
}

# Propensity scores, one per row, in the original row order.
fit_propensity <- function(X, D, method = ps_method) {
  if (method == "xgb") {
    dall <- xgboost::xgb.DMatrix(data.matrix(X), label = D, missing = NA)
    cv <- xgboost::xgb.cv(params = xgb_params, data = dall, nrounds = xgb_max_rounds,
                          nfold = xgb_nfold, early_stopping_rounds = xgb_early_stop,
                          verbose = 0)
    best <- which.min(cv$evaluation_log$test_logloss_mean)   # works across xgboost versions
    fit  <- xgboost::xgb.train(params = xgb_params, data = dall, nrounds = best, verbose = 0)
    p <- predict(fit, dall)
    attr(p, "nrounds") <- best
  } else {
    Xl <- X[, intersect(names(X), confounders), drop = FALSE]
    if ("age" %in% names(Xl) && anyNA(Xl$age)) {               # glm cannot take NA
      Xl$age_missing <- as.integer(is.na(Xl$age))
      Xl$age[is.na(Xl$age)] <- median(Xl$age, na.rm = TRUE)
    }
    fit <- suppressWarnings(glm(D ~ ., data = cbind(D = D, Xl), family = binomial()))
    p <- unname(fitted(fit))
    attr(p, "nrounds") <- NA
  }
  p
}

prep_confounders <- function(X) {
  Xc <- X[, intersect(names(X), confounders), drop = FALSE]
  if ("age" %in% names(Xc) && anyNA(Xc$age)) {
    Xc$age_missing <- as.integer(is.na(Xc$age))
    Xc$age[is.na(Xc$age)] <- median(Xc$age, na.rm = TRUE)
  }
  Xc[, vapply(Xc, function(v) length(unique(v)) > 1, logical(1)), drop = FALSE]
}

ate_weights <- function(D, p) ifelse(D == 1, 1 / p, 1 / (1 - p))

wmean <- function(x, w) sum(w * x, na.rm = TRUE) / sum(w[!is.na(x)])
wvar  <- function(x, w) { m <- wmean(x, w); sum(w * (x - m)^2, na.rm = TRUE) / sum(w[!is.na(x)]) }

# Standardized mean differences before and after weighting.
# Denominator: pooled SD of the two arms before weighting, so the two columns
# are on the same scale (Austin and Stuart 2015).
smd_table <- function(X, D, w) {
  out <- lapply(names(X), function(v) {
    x <- X[[v]]; t1 <- D == 1; t0 <- D == 0
    sd_pool <- sqrt((var(x[t1], na.rm = TRUE) + var(x[t0], na.rm = TRUE)) / 2)
    if (!is.finite(sd_pool) || sd_pool == 0) return(NULL)
    data.frame(covariate  = v,
               smd_before = (mean(x[t1], na.rm = TRUE) - mean(x[t0], na.rm = TRUE)) / sd_pool,
               smd_after  = (wmean(x[t1], w[t1]) - wmean(x[t0], w[t0])) / sd_pool)
  })
  do.call(rbind, out)
}

ess <- function(w) sum(w)^2 / sum(w^2)                     # Kish effective sample size

overlap_plot <- function(p, D, title) {
  br <- seq(0, 1, by = 0.025)
  h1 <- hist(p[D == 1], breaks = br, plot = FALSE)
  h0 <- hist(p[D == 0], breaks = br, plot = FALSE)
  ymax <- max(h1$counts, h0$counts, 1)
  plot(NA, xlim = c(0, 1), ylim = c(-ymax, ymax), xlab = "Propensity score",
       ylab = "Count (treated up, control down)", main = title, cex.main = 0.8)
  rect(br[-length(br)], 0, br[-1],  h1$counts, col = "grey40", border = "white")
  rect(br[-length(br)], 0, br[-1], -h0$counts, col = "grey75", border = "white")
  abline(h = 0)
}

# One full analysis: propensity model, weights, diagnostics, weighted estimate.
run_one <- function(d, group, trt_name) {
  set.seed(seed)
  D <- treatments[[trt_name]]$make(d)
  y <- d$mh_scale
  n1 <- sum(D == 1); n0 <- sum(D == 0)
  base <- data.frame(group = group, treatment = treatments[[trt_name]]$label,
                     n = nrow(d), n_treated = n1, n_control = n0)
  if (min(n1, n0) < 5) {                                    # too few to estimate
    base$note <- "fewer than 5 in one arm; not estimated"
    return(list(result = base, balance = NULL, p = NULL, D = D))
  }

  X <- build_covariates(d, trt_name)
  p <- fit_propensity(X, D)
  w <- ate_weights(D, p)
  bal <- smd_table(X, D, w)

  fit <- lm_robust(y ~ D, weights = w, se_type = "HC2", alpha = alpha)
  # Doubly robust: same weights, plus the confounders in the outcome model
  dr  <- lm_robust(y ~ ., data = cbind(y = y, D = D, prep_confounders(X)),
                   weights = w, se_type = "HC2", alpha = alpha)
  raw_diff <- mean(y[D == 1]) - mean(y[D == 0])

  res <- cbind(base, data.frame(
    estimate        = unname(coef(fit)["D"]),
    std_error       = unname(fit$std.error["D"]),
    ci_lower        = unname(fit$conf.low["D"]),
    ci_upper        = unname(fit$conf.high["D"]),
    p_value         = unname(fit$p.value["D"]),
    std_effect      = unname(coef(fit)["D"]) / sd(raw$mh_scale),  # in outcome SD units
    dr_estimate     = unname(coef(dr)["D"]),
    dr_ci_lower     = unname(dr$conf.low["D"]),
    dr_ci_upper     = unname(dr$conf.high["D"]),
    dr_p_value      = unname(dr$p.value["D"]),
    raw_difference  = raw_diff,                                   # unweighted difference in means
    ps_min          = min(p), ps_max = max(p),
    weight_min      = min(w), weight_median = median(w), weight_max = max(w),
    ess_treated     = ess(w[D == 1]), ess_control = ess(w[D == 0]),
    max_abs_smd_before = max(abs(bal$smd_before)),
    max_abs_smd_after  = max(abs(bal$smd_after)),
    n_smd_over_cutoff_before = sum(abs(bal$smd_before) > smd_cutoff),
    n_smd_over_cutoff_after  = sum(abs(bal$smd_after)  > smd_cutoff),
    n_covariates    = ncol(X),
    xgb_nrounds     = attr(p, "nrounds"),
    note            = ""
  ))
  flags <- c(if (any(p < 0.01 | p > 0.99)) "propensities near 0 or 1 (positivity)",
             if (max(abs(bal$smd_after)) > smd_cutoff) "imbalance remains after weighting")
  res$note <- paste(flags, collapse = "; ")

  if (n_boot > 0) {                                         # whole-pipeline bootstrap
    boots <- replicate(n_boot, {
      i  <- sample.int(nrow(d), replace = TRUE)
      Di <- D[i]
      if (min(sum(Di), sum(1 - Di)) < 2) return(NA)
      pi <- fit_propensity(X[i, , drop = FALSE], Di)
      wi <- ate_weights(Di, pi)
      wmean(y[i][Di == 1], wi[Di == 1]) - wmean(y[i][Di == 0], wi[Di == 0])
    })
    res$boot_ci_lower <- quantile(boots, alpha / 2, na.rm = TRUE)
    res$boot_ci_upper <- quantile(boots, 1 - alpha / 2, na.rm = TRUE)
  }

  bal$group <- group; bal$treatment <- treatments[[trt_name]]$label
  list(result = res, balance = bal, p = p, D = D)
}

# ----------------------------------------------------------------------------
# 5. Run every analysis
# ----------------------------------------------------------------------------
results <- list(); balance <- list()
pdf(file.path(out_dir, "overlap_plots.pdf"), width = 8.5, height = 11)
par(mfrow = c(4, 3), mar = c(4, 4, 3, 1))
for (a in plan) {
  d <- raw[a$rows(raw), , drop = FALSE]
  for (t in a$trt) {
    cat(sprintf("%-24s %-50s", a$group, treatments[[t]]$label))
    r <- run_one(d, a$group, t)
    cat(sprintf(" n=%3d  est=% .3f\n", r$result$n,
                if (is.null(r$result$estimate)) NA else r$result$estimate))
    results[[length(results) + 1]] <- r$result
    if (!is.null(r$balance)) {
      balance[[length(balance) + 1]] <- r$balance
      overlap_plot(r$p, r$D, paste(a$group, "|", treatments[[t]]$label))
    }
  }
}
dev.off()

fill_cols <- function(lst) {                                # rbind with differing columns
  cols <- unique(unlist(lapply(lst, names)))
  do.call(rbind, lapply(lst, function(x) { x[setdiff(cols, names(x))] <- NA; x[cols] }))
}
results <- fill_cols(results)
balance <- do.call(rbind, balance)

# Benjamini-Hochberg adjustment across all estimates (exploratory subgroups)
results$p_value_BH    <- p.adjust(results$p_value,    method = "BH")
results$dr_p_value_BH <- p.adjust(results$dr_p_value, method = "BH")

write.csv(results, file.path(out_dir, "results.csv"), row.names = FALSE)
write.csv(balance, file.path(out_dir, "balance.csv"), row.names = FALSE)
writeLines(capture.output(sessionInfo()), file.path(out_dir, "session_info.txt"))

# ----------------------------------------------------------------------------
# 6. Console summary
# ----------------------------------------------------------------------------
show <- results[, c("group", "treatment", "n", "n_treated", "n_control",
                    "estimate", "ci_lower", "ci_upper", "p_value",
                    "dr_estimate", "dr_ci_lower", "dr_ci_upper", "dr_p_value",
                    "raw_difference", "weight_max", "max_abs_smd_after")]
num <- vapply(show, is.numeric, logical(1))
show[num] <- lapply(show[num], round, 3)
print(show, row.names = FALSE)
cat("\nModels with any |SMD| >", smd_cutoff, "after weighting:",
    sum(results$n_smd_over_cutoff_after > 0, na.rm = TRUE), "of", nrow(results), "\n")
cat("Outputs written to", normalizePath(out_dir), "\n")
