# Codebook: `numeric_GPA3_0_first.csv`

One row per student (n = 295). Survey administered online (REDCap) between April 9 and
June 3, 2020, at a large public university in the Mid-Atlantic United States.

## Outcome

| Variable | Description |
|---|---|
| `mh_scale` | Mean of the 21 DASS-21 items (depression, anxiety, stress), range 0 to 3. Higher = more distress. **Outcome.** |

## Treatments and their source variables

| Variable | Description | Treatment contrast used |
|---|---|---|
| `gpa_thresh3_0` | 1 if self-reported cumulative GPA is 3.0 or below, 0 otherwise | GPA ≤ 3.0 |
| `ptsd_score` | PTSD Checklist for DSM-5 (PCL-5) total, range 0 to 80 | PTSD score ≥ 33 (probable PTSD; not a diagnosis) |
| `covid_iso` | Perceived isolation due to COVID-19, 0 (strongly disagree) to 10 (strongly agree) | Isolation > 7 |
| `edu.i_count` | Number of network members providing intense educational help (0 to 7) | Three or more |
| `max.emohelp` | Highest emotional-help rating of any network member (0 to 10) | 9 or higher |
| `acpers` | Academic perseverance (1 to 6) | Above the full-sample median (4.5) |
| `trauma_sum` | Trauma item sum. **Higher values mean fewer reported traumatic experiences.** | Above the full-sample median (10) |
| `gender` | 0 = cisgender woman, 1 = cisgender man, 2 = gender minority | Not a cisgender woman (PTSD strata only) |

## Stratification variables

| Variable | Coding |
|---|---|
| `ptsd_score` | High symptom severity if ≥ 33, low if < 33 |
| `gender` | 0 = cisgender woman, 1 = cisgender man, 2 = gender minority (not stratified, n = 14) |
| `race` | 0 = White, 1 = Black, Latinx, and other identities, 2 = Asian/Asian-American |
| `age` | Age in years. **0 codes a missing value** (80 students). Grouped as 18 to 20, 21 to 24, 25+ |

## Covariates

| Variable(s) | Description |
|---|---|
| `first_gen` | First-generation college student (1 = yes) |
| `stem_notstem` | STEM field of study (1 = STEM) |
| `hours` | Hours worked |
| `has_mother`, `has_father` | Mother / father listed in the student's support network |
| `role_family`, `role_friend`, `role_sigother`, `role_other` | Roles of the members listed in the support network |
| `prime_count` | Number of prime supporters in the network |
| `edu.r_count`, `edu.i_count`, `emo.r_count`, `emo.i_count` | Counts of network members providing educational (`edu`) or emotional (`emo`) help; `i` = intense help |
| `has_r.<help>.<role>`, `has_i.<help>.<role>` | Indicators that a network member of the given role (`family`, `friend`, `so` = significant other, `other`) provided educational or emotional help; `i` = intense help |
| `max.eduhelp`, `max2.eduhelp`, `max.emohelp`, `max2.emohelp` | Highest and second-highest educational / emotional help ratings in the network (0 to 10) |
| `max.eduhelp.close`, `max.emohelp.close` | Highest educational / emotional help ratings among close contacts |
| `n4.closeness`, `n3.closeness`, `n2orless.closeness` | Number of network members at each closeness level (0 to 4 scale) |
| `ss_family`, `ss_friend`, `ss_sigother` | Perceived social support from family, friends, and a special person (MSPSS subscale means) |
| `ss_community` | Perceived support from the broader community |
| `colearn` | Collective learning (academic engagement with peers) |
| `covid_edu` | Educational disruption due to COVID-19 (0 to 10) |

## Excluded from all propensity score models

| Variable | Reason |
|---|---|
| `record_id` | Identifier |
| `mh_scale` | Outcome |
| `covid_mh` | Self-reported effect of COVID-19 on mental health (0 to 10); a proxy for the outcome |
