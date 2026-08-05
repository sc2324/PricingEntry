/*******************************************************************************
clean_prices.do

Converts the four IQVIA US extracts into .dta files with a consistent format:
one row = corporation x molecule x strength x quarter (x branded flag), with
total standard units and total manufacturer revenue (LCD = USD for the US).
Then appends the four into one combined panel.

Inputs:  ../input/IQVIA_2004-2008.xlsx
         ../input/IQVIA_2009-2010.xlsx
         ../input/IQVIA_2011-2016.xlsx
         ../input/IQVIA_2017-2019.csv
Outputs: ../output_local/iqvia_2004_2008.dta
         ../output_local/iqvia_2009_2010.dta
         ../output_local/iqvia_2011_2016.dta
         ../output_local/iqvia_2017_2019.dta
         ../output_local/iqvia_panel_2004_2019.dta   (all four appended)

Data conventions verified against the raw files:
 - Standard units (SU) are already pack-size-adjusted: SU = packs x pack size,
   i.e. one SU = one tablet/capsule. Verified: (i) in 2011-2016 every row has
   Standard Units = Units x Pack Size; (ii) Lipitor 20mg/90 retail Q1 2004 has
   UNITS 2,487,371 x 90 = 223,863,390 ~ SU 223,863,382, implying $2.79/tab.
   Hence summing SU across pack sizes is valid.
 - Revenue: 2004-2010 extracts report LCD MNF only; local currency = USD for
   the US, so rev_usd = rev_lcd there. 2011+ extracts report both US$ MNF and
   LC$ MNF (equal in the data).
 - FDCs: 2004-2010 use '#'-separated Molecule List with one duplicated row
   per ingredient; 2011+ use '!'-separated molecule fields (2011-2016 also
   duplicates rows across ingredient salts). We keep single-ingredient
   products only, and de-duplicate identical rows after dropping the salt
   column so multi-salt row expansions are not double-counted.
 - Branded flag (heuristic): a product is coded generic if (a) its name
   contains the first word of the molecule name (ATORVASTATIN MYL); (b) its
   first word (>=8 chars) is a prefix of the molecule name -- IQVIA
   truncates long names to ~13 chars (METOCLOPRAMID TEVA); (c) it carries
   IQVIA's unbranded-commodity suffix 'STCE'; (d) its first word is
   shared by >=3 corporations within the molecule (abbreviations like HCTZ,
   store-brand OTC names); or (e) the corporation's name or its 4-char
   code appears in the product name (MKES = MCKESSON), guarded by >=2
   corporations sharing the product first word (catches synonym-named
   generics: ALBUTEROL under SALBUTAMOL, ASPIRIN under ACETYLSALICYLIC
   ACID). Otherwise branded (e.g. LIPITOR, REGLAN).
 - A corporation-molecule-strength-quarter cell that contains both branded
   and generic products (rare, e.g. authorized generics under the same
   corporation) appears as two rows distinguished by `branded'.
 - Firm names are NOT harmonized across the four extracts (IQVIA restates
   names after M&A), so firm-level linking across segments is unreliable;
   drug-level aggregates are safe.
*******************************************************************************/

version 18
clear all
set more off
set excelxlsxlargefile on

local IN  "../input"
local OUT "../output_local"

*------------------------------------------------------------------------------
* Helper: branded/generic flag from product vs molecule name
*------------------------------------------------------------------------------
capture program drop flag_branded
program define flag_branded
    args product molecule corporation
    tempvar prod mol1 pw1 tagcp ncorp
    gen `prod' = strtrim(`product')
    gen `mol1' = word(strtrim(`molecule'), 1)
    gen `pw1'  = word(`prod', 1)
    * corporations sharing this product first-word within the molecule:
    * brand names belong to one corporation; commodity names (HCTZ, VITAMIN)
    * and truncated molecule names are shared by many
    egen `tagcp' = tag(`molecule' `pw1' `corporation')
    egen `ncorp' = total(`tagcp'), by(`molecule' `pw1')
    * rule (e): the corporation appears in the product name -- either the
    * corporation's first word (>=4 chars) as a word of the product, or a
    * 4-character corporation code as the product's last word (IQVIA codes
    * are anchored subsequences of the corporation name: MKES = MCKESSON,
    * WTSN = WATSON). Guarded by >=2 corporations sharing the product first
    * word within the molecule, so single-source brands that also carry a
    * code (ZYRTEC J.J., MARINOL ABBV) stay branded. Catches generics named
    * by molecule synonyms (ALBUTEROL under SALBUTAMOL, ASPIRIN under
    * ACETYLSALICYLIC ACID) that the molecule-name rules miss.
    tempvar cw1 wordmatch lw lwc corpc codematch pos
    gen `cw1' = word(strtrim(`corporation'), 1)
    gen byte `wordmatch' = strlen(`cw1') >= 4 & ///
        strpos(" " + `prod' + " ", " " + `cw1' + " ") > 0
    gen `lw' = word(`prod', -1)
    gen `lwc' = ustrregexra(`lw', "[^A-Z]", "")
    gen `corpc' = ustrregexra(strtrim(`corporation'), "[^A-Z]", "")
    gen byte `codematch' = strlen(`lw') == 4 & wordcount(`prod') >= 2 & ///
        strlen(`lwc') >= 2 & substr(`lwc', 1, 1) == substr(`corpc', 1, 1)
    gen long `pos' = 1
    forvalues i = 2/4 {
        tempvar np
        gen long `np' = strpos(substr(`corpc', `pos' + 1, .), ///
            substr(`lwc', `i', 1)) if `codematch' & strlen(`lwc') >= `i'
        replace `codematch' = 0 if `codematch' & strlen(`lwc') >= `i' & `np' == 0
        replace `pos' = `pos' + `np' if `codematch' & strlen(`lwc') >= `i'
        drop `np'
    }
    * generic if (a) molecule name appears in product name; (b) product first
    * word (>=8 chars) is a prefix of the molecule name -- IQVIA truncates
    * long names to ~13 chars (METOCLOPRAMIDE -> 'METOCLOPRAMID TEVA');
    * (c) unbranded-commodity suffix STCE; (d) first word shared by >=3
    * corporations within the molecule (catches abbreviations like HCTZ and
    * store-brand OTC names); (e) corporation-name match as above with the
    * >=2-corporation guard
    gen byte branded = !( strpos(`prod', `mol1') > 0 ///
        | (strlen(`pw1') >= 8 & strpos(`mol1', `pw1') == 1) ///
        | regexm(`prod', "STCE$") ///
        | `ncorp' >= 3 ///
        | ((`wordmatch' | `codematch') & `ncorp' >= 2) )
    label var branded "1=branded, 0=generic/unbranded (heuristic from product name)"
end

*------------------------------------------------------------------------------
* Helper: final formatting shared by all four segments
*------------------------------------------------------------------------------
capture program drop finalize_segment
program define finalize_segment
    args outfile
    order corporation molecule strength atc3 qdate branded su rev_lcd rev_usd
    format qdate %tq
    label var corporation "Corporation (as named in this extract)"
    label var molecule    "Molecule (single-ingredient products only)"
    label var strength    "International strength"
    label var atc3        "ATC3 class (first observed; missing in 2011-2016)"
    label var qdate       "Quarter"
    label var su          "Total standard units (1 SU = 1 tab/cap; pack-size adjusted)"
    label var rev_lcd     "Total LCD MNF revenue (USD, local currency = USD)"
    label var rev_usd     "Total USD MNF revenue"
    isid corporation molecule strength branded qdate
    sort corporation molecule strength branded qdate
    * keep molecule a fixed-width str, never strL (strL cannot key a reshape)
    recast str244 molecule
    compress
    save "`outfile'", replace
    di as result "Saved `outfile': " _N " rows"
end

*==============================================================================
* Segments 1 & 2: 2004-2008 and 2009-2010
* Long in Measure (LCD MNF / EURO MNF / LCEURO MNF / UNITS / SU / CU),
* wide in quarters (Q1 2004 ... ). Shared column names -> one program.
*==============================================================================
capture program drop clean_measure_long
program define clean_measure_long
    args xlsxfile outfile

    import excel using "`xlsxfile'", firstrow clear
    keep Corporation Molecule MoleculeList InternationalProduct ///
        InternationalStrength ATC3 Measure Q*

    * Keep single-ingredient products ('#' separates FDC ingredients)
    drop if strpos(MoleculeList, "#") > 0
    drop MoleculeList

    keep if inlist(Measure, "LCD MNF", "SU")

    * Molecule -> ATC3 map (merged back after the measure reshape)
    preserve
        keep Molecule ATC3
        duplicates drop
        bysort Molecule (ATC3): keep if _n == 1
        rename (Molecule ATC3) (molecule atc3)
        tempfile atcmap
        save `atcmap'
    restore
    drop ATC3

    * De-duplicate identical rows (guards against attribute-expansion dups)
    duplicates drop

    flag_branded InternationalProduct Molecule Corporation
    drop InternationalProduct

    * Quarters wide -> long. Q12004 -> v20041
    foreach v of varlist Q* {
        local q = substr("`v'", 2, 1)
        local y = substr("`v'", 3, 4)
        rename `v' v`y'`q'
    }
    gen long rowid = _n
    reshape long v, i(rowid) j(yq)
    drop if missing(v)
    gen int qdate = yq(floor(yq/10), mod(yq, 10))

    * Collapse to corporation-molecule-strength-branded-quarter by measure,
    * then spread the two measures back into columns
    gen mtag = cond(Measure == "LCD MNF", "rev_lcd", "su")
    rename (Corporation Molecule InternationalStrength) ///
        (corporation molecule strength)
    collapse (sum) v, by(corporation molecule strength branded qdate mtag)
    reshape wide v, i(corporation molecule strength branded qdate) j(mtag) string
    rename (vrev_lcd vsu) (rev_lcd su)
    gen double rev_usd = rev_lcd    // local currency = USD for the US

    merge m:1 molecule using `atcmap', keep(master match) nogenerate
    finalize_segment `outfile'
end

clean_measure_long "`IN'/IQVIA_2004-2008.xlsx" "`OUT'/iqvia_2004_2008.dta"
clean_measure_long "`IN'/IQVIA_2009-2010.xlsx" "`OUT'/iqvia_2009_2010.dta"

*==============================================================================
* Segment 3: 2011-2016
* Wide in quarter x measure ('Q1 2011_US$ MNF', ...), one row per pack x salt.
* No ATC columns in this extract.
*==============================================================================
import excel using "`IN'/IQVIA_2011-2016.xlsx", firstrow clear

* Rename quarter-measure columns to stubs rev_usd/rev_lcd/su + yq; drop the
* rest (EURO, LCEURO, Units, Counting Units). import excel sanitizes headers
* ('Q1 2011_US$ MNF' -> Q12011_USMNF) and keeps the original in the variable
* label, so match on the label first and fall back to the sanitized name.
foreach v of varlist _all {
    local lab : variable label `v'
    local stub ""
    local y ""
    local q ""
    if regexm(`"`lab'"', "^Q([1-4]) (20[0-9][0-9])_(.+)$") {
        local q = regexs(1)
        local y = regexs(2)
        local m = regexs(3)
        if      `"`m'"' == "US$ MNF"        local stub "rev_usd"
        else if `"`m'"' == "LC$ MNF"        local stub "rev_lcd"
        else if `"`m'"' == "Standard Units" local stub "su"
        else                                drop `v'
    }
    else if regexm("`v'", "^Q([1-4])(20[0-9][0-9])_(.+)$") {
        local q = regexs(1)
        local y = regexs(2)
        local m = regexs(3)
        if      "`m'" == "USMNF"         local stub "rev_usd"
        else if "`m'" == "LCMNF"         local stub "rev_lcd"
        else if "`m'" == "StandardUnits" local stub "su"
        else                             drop `v'
    }
    if "`stub'" != "" rename `v' `stub'`y'`q'
}
confirm variable rev_usd20111 rev_lcd20111 su20111 rev_usd20164

* Keep single-ingredient products ('!' separates FDC ingredients)
drop if strpos(CombinedMolecule, "!") > 0

keep Corporation CombinedMolecule IntProduct IntStrength rev_usd* rev_lcd* su*

* Rows are duplicated across ingredient salts with identical values; the salt
* column is already gone, so exact-duplicate rows are the expansion artifact
duplicates drop

flag_branded IntProduct CombinedMolecule Corporation
drop IntProduct

gen long rowid = _n
reshape long rev_usd rev_lcd su, i(rowid) j(yq)
drop if missing(rev_usd) & missing(rev_lcd) & missing(su)
gen int qdate = yq(floor(yq/10), mod(yq, 10))

rename (Corporation CombinedMolecule IntStrength) (corporation molecule strength)
collapse (sum) rev_usd rev_lcd su, by(corporation molecule strength branded qdate)
gen atc3 = ""
finalize_segment "`OUT'/iqvia_2011_2016.dta"

*==============================================================================
* Segment 4: 2017-2019 (csv)
* Fully long: one row per pack x quarter, measures in columns. Numeric values
* are quoted with thousands separators -> import as strings and destring.
*==============================================================================
import delimited using "`IN'/IQVIA_2017-2019.csv", ///
    varnames(1) case(lower) stringcols(_all) clear

keep corporation moleculelist internationalproduct internationalstrength ///
    atc3 calendarquarter usdmnf lcdmnf standardunits

* Keep single-ingredient products ('!' separates FDC ingredients)
drop if strpos(moleculelist, "!") > 0

destring usdmnf lcdmnf standardunits, replace ignore(",")

* De-duplicate rows repeated across ingredient salts (salt column not kept)
duplicates drop

flag_branded internationalproduct moleculelist corporation
drop internationalproduct

gen int qdate = quarterly(substr(calendarquarter, 4, 4) + "q" + ///
    substr(calendarquarter, 2, 1), "YQ")
assert !missing(qdate)

rename (moleculelist internationalstrength usdmnf lcdmnf standardunits) ///
    (molecule strength rev_usd rev_lcd su)
collapse (sum) rev_usd rev_lcd su (firstnm) atc3, ///
    by(corporation molecule strength branded qdate)
finalize_segment "`OUT'/iqvia_2017_2019.dta"

*==============================================================================
* Combined panel: append the four segments
* (firm names are not harmonized across segments -- see header note)
*==============================================================================
use "`OUT'/iqvia_2004_2008.dta", clear
gen byte segment = 1
append using "`OUT'/iqvia_2009_2010.dta"
replace segment = 2 if missing(segment)
append using "`OUT'/iqvia_2011_2016.dta"
replace segment = 3 if missing(segment)
append using "`OUT'/iqvia_2017_2019.dta"
replace segment = 4 if missing(segment)

label define segment 1 "2004-2008" 2 "2009-2010" 3 "2011-2016" 4 "2017-2019"
label values segment segment
label var segment "Source extract (firm names not harmonized across segments)"

isid corporation molecule strength branded qdate
sort molecule strength qdate corporation branded
compress
save "`OUT'/iqvia_panel_2004_2019.dta", replace
di as result "Saved combined panel: " _N " rows"

* Quick sanity summary
tab segment branded
bysort segment: sum su rev_usd
