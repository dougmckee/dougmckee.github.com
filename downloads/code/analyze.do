
/* 
* Analyze articles published on High Variance in 2012 and 2013
*
* BTW: UCLA has way better documentation of file read than Stata:
*      http://www.ats.ucla.edu/stat/stata/faq/fileread.htm
*
*/

set more off

capture log close
log using analyze.log ,replace

global DEST "../source/images/analyze-2014-02-09"

capture program drop parse_post
capture program drop load_year_posts
file close _all

/* Given the name of a Markdown document, parse it and return its
   title, date (of publication), tags, and wordcount.
*/
program define parse_post ,rclass
    local mdfile "`1'"

    tempname fh
    file open `fh' using `mdfile' ,read
    
    local donewithyaml=0
    local wordcount=0
    /* Assume first line is just "---" marking beginning of YAML header */
    file read `fh' line
    file read `fh' line
    while r(eof)==0 {
      * di `"LINE :`line':"'
      if (!`donewithyaml') { // Parse header
        if (`"`line'"'=="---") {
           local donewithyaml = 1
        }
        else {
          local key = ""
          local value = ""
          if regexm(`"`line'"',`"([a-zA-z-]+): ["]*([^"]*)["]*"') {
            local key = regexs(1)
            local value = regexs(2)
            * di `"KEY: `key'"'
            * di `"VALUE: `value'"'
            if ("`key'"=="date") {
              local date = date("`value'", "YMD")
            }
            if ("`key'"=="categories") {
              local tags = "`value'"
            }
            if ("`key'"=="title") {
              local title = "`value'"
            }
          }
        }
      }
      else { // Count words in body of post
        local wcl = wordcount(`"`line'"')
        * display `"wordcount(`line'): `wcl'"'
        local wordcount = `wordcount' + `wcl'
      }
      file read `fh' line
    }
    file close `fh'
    
    return local title = "`title'"
    return scalar date = `date'
    return local tags = "`tags'"
    return scalar wordcount = `wordcount'

end

/* Given a year, load in the stats (using parse_post) for each article.
   The resulting data set is one observation per post. It also creates dummy 
   variables for each referenced tag.
*/
program define load_year_posts
    local year "`1'"
    ! ls ~/octopress/source/_posts/`year'-* > /tmp/`year'-filelist.txt
    
    tempname fh
    file open `fh' using "/tmp/`year'-filelist.txt" ,read
    file read `fh' line
    local i 1
    qui set obs 1
    qui gen title=""
    qui gen tags=""
    qui gen wordcount=.
    qui gen postdate=.
    while r(eof)==0 {
      qui set obs `i'
      parse_post "`line'"
      qui replace title = `"`r(title)'"' if _n==`i'
      qui replace tags = "`r(tags)'" if _n==`i'
      qui replace postdate = r(date) if _n==`i'
      qui replace wordcount = r(wordcount) if _n==`i'
      local ntags = wordcount(r(tags))
      forval j = 1/`ntags' {
        local tag = subinstr(word(r(tags),`j'),"-","_",.)
        capture confirm var tag_`tag'
        if _rc != 0 {
          qui gen tag_`tag'=.
        }
        qui replace tag_`tag'=1 if _n==`i'
      }
      local i = `i' + 1
      file read `fh' line
    }
    file close `fh'
    foreach tagvar of varlist tag_* {
      qui replace `tagvar'=0 if `tagvar'==.
    }
    gen year=`year'
end

/* Load up 2012 and 3013 */

clear
load_year_posts 2012
tempfile y2012
save `y2012'
clear
load_year_posts 2013
append using `y2012'

local tags "tech politics thanks education kids economics music productivity conan kbr photo mundane christmas blog"

/* Are there any articles that do not have one of the above tags? */

local tagvars ""
local ifclause "if 1 "
local yvaroptions "yvaroptions(relabel("
local i=1
foreach t in `tags' {
  local tagvars = "`tagvars' tag_`t'"
  local ifclause = "`ifclause ' & tag_`t'==0"
  local yvaroptions `"`yvaroptions'`i' "`t'" "'
  local i = `i' + 1
}
local yvaroptions `"`yvaroptions'))"'
count `ifclause'
list title tags `ifclause'

di `"`yvaroptions'"'

/* Draw lots of pretty pictures.
*  Thanks Michael Mitchell for your awesome _Visual Guide to Stata Graphics_ Third Edition!
*/

graph hbar (sum) `tagvars' ,ascategory over(year) `yvaroptions' b1title("Article Count by tag")
graph export $DEST/tags.png ,replace

// Thanks for the overlaid histogram ATS!
// http://www.ats.ucla.edu/stat/stata/faq/histogram_overlay.htm

twoway (histogram wordcount if year==2012 ,frequency start(0) width(100) color(navy)) ///
       (histogram wordcount if year==2013 ,frequency start(0) width(100) fcolor(none) lcolor(black)) ///
       ,xtitle("") ytitle("Word Count Frequency") legend(label(1 "2012") label(2 "2013"))
graph export $DEST/wchist.png ,replace

bysort year: summarize wordcount ,detail

gen month = month(postdate)

gen ac=1
graph bar (sum) ac ,over(year) over(month) asyvars ///
      b1title("Month") ytitle("Article Count")
graph export $DEST/ac.png ,replace

graph bar (sum) wordcount ,over(year) over(month) asyvars ///
      b1title("Month") ytitle("Word Count")
graph export $DEST/wc.png ,replace

collapse (sum) ac wordcount ,by(year)
list

log close
