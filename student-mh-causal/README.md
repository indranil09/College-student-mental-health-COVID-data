# Propensity score analysis of college student mental health in early COVID-19

Data, code, and output for

> Shearer E, Páez Carrión N, Jackson J, Amona E, Qian Y, Chan D, Sahoo I.
> *A causal analysis of academic, psychological, and social influences on college student
> mental health during the COVID-19 pandemic.* PLOS Mental Health (under revision).

The study estimates the effects of academic performance, PTSD symptom severity, COVID-19
isolation, educational and emotional support, academic perseverance, gender identity, and
trauma history on psychological distress (DASS-21) among 295 students surveyed between
April 9 and June 3, 2020. Effects are estimated by inverse probability weighting with
XGBoost propensity scores, in the full sample and within exploratory subgroups defined by
PTSD symptom severity, gender identity, race, and age.

**Start with the vignette:** [view it online](https://indranil09.github.io/College-student-mental-health-COVID-data/student-mh-causal/vignette/vignette.html) (source: [`vignette/vignette.Rmd`](vignette/vignette.Rmd)). It walks through
the data, treatment definitions, causal assumptions, weighting diagnostics, all 46 estimates
(Tables 3 to 7), and the Benjamini and Hochberg adjustment.

## Contents

| Path | Description |
|---|---|
| `data/numeric_GPA3_0_first.csv` | De-identified analytic dataset (295 students, 56 variables) |
| `data/codebook.md` | Variable definitions and coding |
| `R/causal_ipw.R` | Complete analysis: propensity scores, weights, diagnostics, estimates, BH adjustment |
| `output/results.csv` | One row per subgroup and treatment: estimates, 90% CIs, p-values, BH p-values, weight and balance summaries (Tables 3 to 7, Supplementary Tables S1 and S2) |
| `output/balance.csv` | Standardized mean difference of every covariate before and after weighting (S1 Data) |
| `output/overlap_plots.pdf` | Propensity score distributions by treatment group (Supplementary Fig S1) |
| `output/session_info.txt` | R and package versions used to produce the output |
| `vignette/vignette.Rmd`, `vignette/vignette.html` | Annotated walkthrough of the analysis and results |

## Reproducing the analysis

Requirements: R (4.6.1 was used), with the packages `xgboost` (3.2.1.1) and `estimatr` (2.0.1).
The vignette additionally uses `rmarkdown`, `dplyr`, `tidyr`, `ggplot2`, `knitr`, and `kableExtra`.

```bash
# from this folder
Rscript R/causal_ipw.R                                    # writes output/
Rscript -e 'rmarkdown::render("vignette/vignette.Rmd")'   # rebuilds the vignette
```

The script fits 46 propensity score models and runs in a few minutes on a laptop. The seed
is fixed (`seed <- 2024`) and XGBoost runs single-threaded, so results are reproducible on
a given platform. Small numerical differences can occur across operating systems or
`xgboost` versions.

## Method in brief

* **Treatments** are binary contrasts. See the vignette, Section 2, for exact definitions.
  Note that `trauma_sum` is scored so that higher values mean *fewer* reported traumatic
  experiences.
* **Propensity scores** come from XGBoost (depth 2, learning rate 0.05, minimum child weight 5,
  subsampling 0.8), with the number of rounds chosen by 5-fold cross-validation and early
  stopping. The covariates are all measured variables except the outcome, the self-reported
  COVID-19 effect on mental health, and the variable the treatment is built from.
* **Weights** are unstabilized, untruncated ATE weights, `w = D/p + (1 - D)/(1 - p)`.
* **Effects** are estimated by weighted least squares of the outcome on the treatment, with HC2
  standard errors (`estimatr::lm_robust`), and 90% confidence intervals (alpha = 0.10).
* **Multiplicity:** Benjamini and Hochberg adjusted p-values are computed across all 46 estimates.

`results.csv` also contains a doubly robust variant (`dr_estimate` and related columns, with
the confounders added to the outcome model). It is provided for reference and is not reported
in the paper.

## Citation

If you use these data or code, please cite the paper above.
