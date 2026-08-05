/*******************************************************************************
price_hysteresis.do

When the number of generic firms rises and then falls back, how complete is
the price reversal? I.e., at the same current firm count n, is the price
after a fall from a higher peak lower than it was on the way up (part of the
competitive price reduction "retained")?

 A. Hysteresis regression (within molecule, quarter FE):
       ln p_g = a_m + d_t + b*ln(n) + g*ln(running max of n) + e
    - complete reversal:  g = 0 (only current n matters)
    - full retention:     b = 0 (only the historical peak matters)
    - share of the up-leg price drop retained after n returns: g/(b+g)
    Robustness: molecule-specific linear trends; molecules with peak>=5;
    levels instead of logs.

 B. Matched-crossings comparison (transparent, no functional form):
    For each molecule with an interior peak, compare the quarter-FE-adjusted
    ln price in quarters with exactly n firms BEFORE the peak vs the same n
    AFTER the peak. delta = ln p(down at n) - ln p(up at n) < 0 means part
    of the reduction is retained.

Notes: p_g is average revenue per SU across a molecule's generic products,
so strength-mix shifts add noise (molecule FE absorbs levels). Selection
works AGAINST finding retention: if low-price firms are the ones that exit,
the surviving-firm average mechanically rises on the down leg.

Input:  ../input/2_build_molecule_panel/output_local/molecule_panel.dta
Output: log tables
*******************************************************************************/

version 18
clear all
set more off

local PANEL "../input/2_build_molecule_panel/output_local/molecule_panel.dta"

use "`PANEL'", clear
keep if n_firms_g >= 1 & su_g > 0 & p_g > 0
egen long molid = group(molecule)
sort molid qdate

gen double lnp = ln(p_g)
gen double lnn = ln(n_firms_g)

* running historical max of the generic firm count
by molid: gen n_runmax = n_firms_g if _n == 1
by molid: replace n_runmax = max(n_runmax[_n-1], n_firms_g) if _n > 1
gen double lnnmax = ln(n_runmax)

* molecule-level quarterly peak and first quarter attaining it
by molid: egen n_qpeak = max(n_firms_g)
gen qifpk = qdate if n_firms_g == n_qpeak
by molid: egen qpeak = min(qifpk)
drop qifpk

*==============================================================================
* A. Hysteresis regressions
*==============================================================================
di as result _n "=== A1. Baseline: ln p on ln n and ln running-max n (mol FE + quarter FE) ==="
reghdfe lnp lnn lnnmax, absorb(molid qdate) vce(cluster molid)
di as result "Retained share of the up-leg price drop after n returns: g/(b+g)"
nlcom retained: _b[lnnmax] / (_b[lnn] + _b[lnnmax])

di as result _n "=== A2. Molecule-specific linear trends ==="
reghdfe lnp lnn lnnmax, absorb(molid qdate molid#c.qdate) vce(cluster molid)
nlcom retained: _b[lnnmax] / (_b[lnn] + _b[lnnmax])

di as result _n "=== A3. Molecules with quarterly peak >= 5 only ==="
reghdfe lnp lnn lnnmax if n_qpeak >= 5, absorb(molid qdate) vce(cluster molid)
nlcom retained: _b[lnnmax] / (_b[lnn] + _b[lnnmax])

di as result _n "=== A4. Levels of n instead of logs ==="
reghdfe lnp n_firms_g n_runmax, absorb(molid qdate) vce(cluster molid)
nlcom retained: _b[n_runmax] / (_b[n_firms_g] + _b[n_runmax])

* worked example: 5 -> 10 -> 5 firms, using the baseline estimates
qui reghdfe lnp lnn lnnmax, absorb(molid qdate) vce(cluster molid)
local drop  = (_b[lnn] + _b[lnnmax]) * ln(2)
local back  = _b[lnn] * ln(5) + _b[lnnmax] * ln(10) - (_b[lnn] + _b[lnnmax]) * ln(5)
di as result _n "Worked example 5 -> 10 -> 5 firms (baseline estimates):"
di as result "  price change going 5->10 firms: " %6.3f `drop' " log points"
di as result "  price at return to 5, relative to original 5-firm price: " %6.3f `back' " log points"

*==============================================================================
* B. Matched crossings: same n before vs after the peak
*==============================================================================
* quarter-FE-adjusted price (aggregate trends/inflation removed)
qui reghdfe lnp, absorb(qdate) residuals(lnp_r)

* keep molecules with an interior peak worth studying
by molid: egen qmin = min(qdate)
by molid: egen qmax = max(qdate)
keep if n_qpeak >= 4 & qpeak > qmin & qpeak < qmax

gen byte phase = cond(qdate < qpeak, 1, cond(qdate > qpeak, 2, .))

* molecule peak price (adjusted), measured in quarters at the peak count
gen lnppk_ = lnp_r if n_firms_g == n_qpeak
by molid: egen lnp_peak = mean(lnppk_)

preserve
    keep if phase != . & n_firms_g < n_qpeak
    collapse (mean) lnp_r (count) nq=lnp_r (first) n_qpeak lnp_peak, ///
        by(molid n_firms_g phase)
    reshape wide lnp_r nq, i(molid n_firms_g n_qpeak lnp_peak) j(phase)
    keep if lnp_r1 != . & lnp_r2 != .

    gen double delta = lnp_r2 - lnp_r1    // down-leg minus up-leg at same n
    gen int gap = n_qpeak - n_firms_g

    di as result _n "=== B1. delta = ln p(down at n) - ln p(up at n), matched pairs ==="
    sum delta, detail
    di as result "Share of pairs with delta < 0 (some reduction retained):"
    count
    count if delta < 0

    di as result _n "=== B2. delta by distance below the peak ==="
    gen str6 gapbin = cond(gap <= 2, "1-2", cond(gap <= 5, "3-5", "6+"))
    tabstat delta, by(gapbin) stat(n mean p25 p50 p75)

    * retained fraction of the up-leg drop (only where the up-leg drop was
    * meaningful: price at n on the way up at least 0.2 log pts above peak)
    gen double retained = (lnp_r1 - lnp_r2) / (lnp_r1 - lnp_peak) ///
        if lnp_r1 - lnp_peak >= 0.2
    di as result _n "=== B3. Retained fraction (pre - post)/(pre - peak-price), up-leg drop >= 0.2 ==="
    sum retained, detail
restore
