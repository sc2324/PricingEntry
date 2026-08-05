/*******************************************************************************
desc_ngen_trajectories.do

Documents the trajectory of the number of generic firms per molecule:
is rise -> peak -> substantial fall a common pattern?

 A. Annual molecule trajectories: peak size/timing, fall from peak to end of
    sample, classification (with explicit censoring categories).
 B. Distribution of end-of-sample count relative to peak; by peak size;
    unweighted and revenue-weighted. Robustness: within the single-vintage
    2011-2016 extract; excluding vitamins/minerals (A11/A12).
 C. Event-time profile of n_generics around the peak year (mechanical descent
    by construction of the max -- magnitude/persistence is the object).
 D. Cohorts around FIRST generic entry (quarterly, no mechanical peak):
    mean firm count and median price ratio by quarters since entry.
 E. Examples: largest-revenue molecules with substantial falls.
 F. Price link: change in log generic price from peak year to end, by fall
    category.

Annual firm count = max over the year's quarters (robust to one-quarter gaps
and to the small vintage-consolidation jumps at extract boundaries).

Input:  ../input/2_build_molecule_panel/output_local/molecule_panel.dta
Output: ../output/fig_peak_eventtime.png
        ../output/fig_entry_cohort.png
        log tables
*******************************************************************************/

version 18
clear all
set more off

local PANEL "../input/2_build_molecule_panel/output_local/molecule_panel.dta"
local FIGOPTS graphregion(color(white)) bgcolor(white) ///
    ylabel(, angle(0) glcolor(gs14)) xlabel(, glcolor(gs14))
local BLUE  "37 99 235"
local GRAY  "107 114 128"

*==============================================================================
* A. Annual molecule-level trajectories and classification
*==============================================================================
use "`PANEL'", clear
gen int year = year(dofq(qdate))
collapse (max) n_gen=n_firms_g n_brd=n_firms_b ///
    (sum) rev_g su_g rev_b, by(molecule atc3 year)
gen double p_g_yr = rev_g / su_g if su_g > 0

* molecule-level stats
bysort molecule: egen n_peak = max(n_gen)
bysort molecule: egen ymin   = min(year)
bysort molecule: egen ymax   = max(year)
gen yearifpeak = year if n_gen == n_peak
bysort molecule: egen ypeak  = min(yearifpeak)
gen nlast_ = n_gen   if year == ymax
gen nfrst_ = n_gen   if year == ymin
gen plast_ = p_g_yr  if year == ymax
gen ppeak_ = p_g_yr  if year == ypeak
bysort molecule: egen n_last = min(nlast_)
bysort molecule: egen n_frst = min(nfrst_)
bysort molecule: egen p_last = min(plast_)
bysort molecule: egen p_peak = min(ppeak_)
bysort molecule: egen totrev = total(rev_g + rev_b)
gen byte vitamin = inlist(substr(atc3, 1, 3), "A11", "A12")

preserve
    bysort molecule: keep if _n == 1
    gen double ratio_last = n_last / n_peak

    gen byte class = .
    replace class = 1 if n_peak == 0
    replace class = 2 if n_peak >= 1 & n_peak <= 2
    replace class = 3 if n_peak >= 3 & ymax <= 2018
    replace class = 4 if n_peak >= 3 & ymax >= 2019 & (2019 - ypeak) < 3
    replace class = 5 if class == . & ratio_last <= 0.5
    replace class = 6 if class == . & ratio_last <= 0.75
    replace class = 7 if class == . & ratio_last <  1
    replace class = 8 if class == . & ratio_last >= 1
    label define class ///
        1 "no generics ever" ///
        2 "low activity (peak 1-2)" ///
        3 "leaves sample before 2019" ///
        4 "peak <3y before end (censored)" ///
        5 "SUBSTANTIAL fall (end <=50% of peak)" ///
        6 "moderate fall (50-75%)" ///
        7 "small fall (75-99%)" ///
        8 "no fall (ends at peak)"
    label values class class

    di as result _n "=== A1. Trajectory classification, all molecules ==="
    tab class

    di as result _n "=== A2. Same, revenue-weighted (share of total sales) ==="
    tab class [aw = totrev]

    di as result _n "=== A3. Judgeable molecules only (peak>=3, >=3y post-peak, in sample thru 2019) ==="
    tab class if inrange(class, 5, 8)
    di as result "Distribution of end/peak ratio among judgeable:"
    sum ratio_last if inrange(class, 5, 8), detail

    di as result _n "=== A4. Judgeable, by peak size ==="
    gen str8 peakbin = cond(n_peak <= 5, "3-5", cond(n_peak <= 10, "6-10", "11+")) ///
        if inrange(class, 5, 8)
    tab peakbin class if inrange(class, 5, 8), row

    di as result _n "=== A5. Robustness: excluding vitamins/minerals (A11/A12) ==="
    tab class if !vitamin

    di as result _n "=== A6. Did the peak follow a rise? (peak vs first-year count, judgeable) ==="
    gen rise = n_peak - n_frst if inrange(class, 5, 8)
    sum rise if inrange(class, 5, 8), detail
    di as result "Share with peak in interior (not first observed year):"
    count if inrange(class, 5, 8)
    count if inrange(class, 5, 8) & ypeak > ymin

    * F. price change from peak year to end, by fall category
    di as result _n "=== F. Change in ln(generic price), peak year -> last year, by class ==="
    gen dlnp_peak_end = ln(p_last) - ln(p_peak) if inrange(class, 5, 8)
    tabstat dlnp_peak_end if inrange(class, 5, 8), by(class) stat(n mean p25 p50 p75)

    * E. examples: largest substantial-fall molecules
    di as result _n "=== E. Top-15 revenue molecules with substantial falls ==="
    gsort -totrev
    gen r5 = sum(class == 5)
    format totrev %14.0fc
    format dlnp_peak_end %6.2f
    list molecule n_peak ypeak n_last dlnp_peak_end totrev ///
        if class == 5 & r5 <= 15, noobs
    tempfile molstats
    save `molstats'
restore

*==============================================================================
* B. Robustness: within the single-vintage 2011-2016 extract only
*==============================================================================
preserve
    keep if inrange(year, 2011, 2016)
    bysort molecule: egen pk  = max(n_gen)
    gen yifpk = year if n_gen == pk
    bysort molecule: egen ypk = min(yifpk)
    bysort molecule: egen ymx = max(year)
    gen nl_ = n_gen if year == ymx
    bysort molecule: egen nl = min(nl_)
    bysort molecule: keep if _n == 1
    keep if pk >= 3 & ymx == 2016 & inrange(ypk, 2011, 2013)
    gen double ratio = nl / pk
    di as result _n "=== B. Single-vintage check (2011-2016 only, peak 2011-13, obs thru 2016) ==="
    di as result "end-2016 count / peak:"
    sum ratio, detail
    count if ratio <= 0.5
    count if ratio <= 0.75
restore

*==============================================================================
* C. Event-time profile around the peak year (interior peaks, peak>=3)
*==============================================================================
preserve
    merge m:1 molecule using `molstats', assert(match) nogenerate ///
        keepusing(n_peak ypeak ymin ymax)
    keep if n_peak >= 3 & ypeak > ymin & ypeak < ymax
    gen tau = year - ypeak
    keep if inrange(tau, -6, 6)
    gen double norm = n_gen / n_peak
    collapse (mean) norm (count) nmol=norm, by(tau)
    di as result _n "=== C. Mean n_gen/peak by years since peak (interior peaks >=3) ==="
    list tau norm nmol, noobs sep(0)
    twoway line norm tau, lcolor("`BLUE'") lwidth(medthick) ///
        `FIGOPTS' ///
        xline(0, lcolor(gs12) lpattern(dash)) ///
        xtitle("Years since peak in # generic firms") ///
        ytitle("Mean n. generic firms / peak") ///
        title("Generic firm count around its peak", color(black) size(medium)) ///
        note("Molecules with interior peak >= 3 firms. Descent after 0 partly mechanical (peak = max).", size(vsmall))
    graph export "../output/fig_peak_eventtime.png", replace width(1600)
restore

*==============================================================================
* D. Cohorts around FIRST generic entry (quarterly; no mechanical peak)
*==============================================================================
use "`PANEL'", clear
gen qifg = qdate if n_firms_g > 0
bysort molecule: egen qentry = min(qifg)
bysort molecule: egen qmin   = min(qdate)
gen bpre_ = n_firms_b if qdate == qentry - 1
bysort molecule: egen bpre = min(bpre_)

* first entry observed with >=1y of generic-free history and a branded
* incumbent in the quarter before entry
keep if qentry != . & qentry - qmin >= 4 & bpre >= 1 & bpre != .
keep if inrange(qentry, tq(2006q1), tq(2015q4))
gen tau = qdate - qentry
keep if inrange(tau, -4, 16)

gen p0_ = p_g if tau == 0
bysort molecule: egen p0 = min(p0_)
gen double prat = p_g / p0

preserve
    collapse (mean) mean_ngen=n_firms_g (p50) med_ngen=n_firms_g ///
        (p50) med_prat=prat (count) nmol=n_firms_g, by(tau)
    di as result _n "=== D. Cohort profile: quarters since first generic entry ==="
    di as result "(entries 2006q1-2015q4 with 1y+ generic-free history and branded incumbent)"
    list tau mean_ngen med_ngen med_prat nmol, noobs sep(4)
    twoway line mean_ngen tau, lcolor("`BLUE'") lwidth(medthick) ///
        `FIGOPTS' ///
        xline(0, lcolor(gs12) lpattern(dash)) ///
        xtitle("Quarters since first generic entry") ///
        ytitle("Mean n. generic firms") ///
        title("Generic firm count after first entry", color(black) size(medium)) ///
        note("Molecules with first generic entry 2006q1-2015q4, 1y+ generic-free history, branded incumbent.", size(vsmall))
    graph export "../output/fig_entry_cohort.png", replace width(1600)
restore

* how many of these entry cohorts have peaked and declined within 4 years?
preserve
    keep if inrange(tau, 0, 16)
    bysort molecule: egen pk = max(n_firms_g)
    gen nl_ = n_firms_g if tau == 16
    bysort molecule: egen nl = min(nl_)
    bysort molecule: keep if _n == 1
    keep if nl != .
    di as result _n "=== D2. Within 4 years of first entry: peak and end-of-window count ==="
    sum pk, detail
    gen double ratio = nl / pk
    sum ratio, detail
    count
    count if ratio <= 0.5
    count if ratio <= 0.75
restore
