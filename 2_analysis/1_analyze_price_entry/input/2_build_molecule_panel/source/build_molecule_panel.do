/*******************************************************************************
build_molecule_panel.do

Builds the molecule x quarter panel for the entry/exit analysis. Firm names
are not harmonized across the four IQVIA extracts (each extract stamps its
vintage's corporate names on all quarters in its window), so the analysis
panel is defined at the molecule level: distinct-corporation counts and
average prices, separately for generic and branded products.

One row = molecule x quarter, with _g (generic) and _b (branded) variables:
  n_firms_*  distinct corporations with positive sales
  su_*       total standard units
  rev_*      total USD MNF revenue
  p_*        average price per standard unit (rev/su)

Input:  ../input/output_local/iqvia_panel_2004_2019.dta
Output: ../output_local/molecule_panel.dta
*******************************************************************************/

version 18
clear all
set more off

use "../input/output_local/iqvia_panel_2004_2019.dta", clear
drop if su <= 0

* molecule is stored as strL in the combined file; reshape keys cannot be strL
recast str244 molecule
compress molecule

* Drop IQVIA catch-all pseudo-molecules (diagnostics kits, devices, cream
* bases, unspecified compositions) -- these are not single molecules and
* their many uniquely-named products inflate branded firm counts.
* (Suffix-anchored so real molecules like TESTOSTERONE are unaffected.)
gen byte pseudo = molecule == "COMPOSITION UNKNOWN" ///
    | molecule == "OTHERS" | strpos(molecule, "OTHER ") == 1 ///
    | inlist(molecule, "MULTIVITAMINS", "MULTIVITAMINS AND MINERALS", ///
        "MINERALS", "TONICS", "GENERAL NUTRIENTS", "NUTRITIONAL SUPPLEMENTS") ///
    | regexm(molecule, "(TESTS?|DEVICES?|PREPARATIONS?)$") ///
    | strpos(molecule, "(BASIS)") > 0
qui count if pseudo
di as result "Dropping " r(N) " molecule-quarter rows from pseudo-molecules"
drop if pseudo
drop pseudo

* Molecule -> ATC3 map (ATC missing in the 2011-2016 extract)
preserve
    keep if atc3 != ""
    keep molecule atc3
    duplicates drop
    bysort molecule (atc3): keep if _n == 1
    tempfile atcmap
    save `atcmap'
restore

egen byte ftag = tag(molecule qdate branded corporation)
collapse (sum) n_firms=ftag su rev=rev_usd, by(molecule qdate branded)

reshape wide n_firms su rev, i(molecule qdate) j(branded)
rename (*0) (*_g)
rename (*1) (*_b)
foreach s in g b {
    replace n_firms_`s' = 0 if missing(n_firms_`s')
    replace su_`s'      = 0 if missing(su_`s')
    replace rev_`s'     = 0 if missing(rev_`s')
    gen double p_`s' = rev_`s' / su_`s' if su_`s' > 0
}

merge m:1 molecule using `atcmap', keep(master match) nogenerate

gen byte segment = 1 + (qdate >= tq(2009q1)) + (qdate >= tq(2011q1)) + ///
    (qdate >= tq(2017q1))
label define segment 1 "2004-2008" 2 "2009-2010" 3 "2011-2016" 4 "2017-2019"
label values segment segment

label var n_firms_g "# distinct corporations, generic (vintage names)"
label var n_firms_b "# distinct corporations, branded (vintage names)"
label var su_g      "Total standard units, generic"
label var su_b      "Total standard units, branded"
label var rev_g     "Total USD MNF revenue, generic"
label var rev_b     "Total USD MNF revenue, branded"
label var p_g       "Avg price per SU, generic (rev/su)"
label var p_b       "Avg price per SU, branded (rev/su)"
label var atc3      "ATC3 (first observed across extracts)"
label var segment   "Source extract (transitions between segments are noisy)"
format qdate %tq

isid molecule qdate
order molecule atc3 qdate segment n_firms_g n_firms_b p_g p_b su_g su_b ///
    rev_g rev_b
sort molecule qdate
compress
save "../output_local/molecule_panel.dta", replace
di as result "Saved molecule_panel.dta: " _N " rows"

* Summary
sum n_firms_g n_firms_b p_g p_b
tab segment
