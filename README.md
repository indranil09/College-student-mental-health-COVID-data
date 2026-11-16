This repository contains the de-identified survey dataset and supporting materials used in two related studies of college students during the early stages of the COVID-19 pandemic. The data include measures of academic performance, support networks, mental health, and pandemic-related experiences.

In the first study, published in the [Journal of Data Science](https://jds-online.org/journal/JDS/article/1264/info), the dataset was used to build machine learning models for predicting students’ self-reported GPA from demographic and support-network variables. In the second study, the same survey framework is used to estimate the causal effects of academic, psychological, and social factors on students’ mental health, with a focus on GPA, PTSD symptoms, COVID-19 isolation, and perceived support.

Together, these studies demonstrate how the same student dataset can be used for both predictive modeling and causal analysis to better understand student well-being during a period of crisis.

## Repository contents

* `numeric_MHTree.csv`: dataset used in the Journal of Data Science study.
* [`student-mh-causal/`](student-mh-causal/): data, analysis code, output, and an annotated vignette for the causal analysis of student mental health (propensity score weighting with XGBoost). See its [README](student-mh-causal/README.md), or view the [interactive vignette](https://indranil09.github.io/College-student-mental-health-COVID-data/student-mh-causal/vignette/vignette.html) online.
