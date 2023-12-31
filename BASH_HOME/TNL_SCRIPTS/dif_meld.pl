#!/usr/bin/perl
# #!/home/utils/perl5/perlbrew/perls/5.26.2-060/bin/perl
##!/home/utils/perl-5.26/5.26.2-058/bin/perl
# This code has been tested on perl 5.6.1 through 5.30
use warnings;
use strict;
use Cwd qw(abs_path cwd);
use Data::Dumper qw(Dumper);
use File::Basename qw(basename dirname);
use File::Find qw(find);
use File::Temp qw(tempdir);
use Getopt::Long qw(GetOptions);
sub say { print @_, "\n" }

# Defaults can be overridden with user config file ~/.dif.defaults  (key/value format)
my %defaults;
$defaults{gui}              = 'gvimdiff';                   # gvimdiff or meld or kompare or kdiff3...
$defaults{meldSizeLimit}    = 2000000;                      # switch to gvimdiff once uncompressed file size is over this limit
$defaults{head}             = 10000;                        # max number of lines used by options -head and -tail
$defaults{history}          = 0;                            # log options used to ~/.dif.history
$defaults{fold}             = 105;                          # columns used by -fold
$defaults{bcpp}             = "/usr/bin/bcpp";              # location of bcpp
$defaults{perltidy}         = "$^X" . "tidy -l=110 -ce";    # perltidy location and options
$defaults{openMultipleGUIs} = 0;                            # when using option -dir2 or -gold, open all GUI windows at the same time
my $MAXHEAD = 99999999999;
my $MINHEAD = 50;
my %opt;

my $scriptName = 'dif';

sub usage {
    my $usage = "\n
'$scriptName' by Chris Koknat  https://github.com/koknat/dif

    Purpose:
        The graphical compare tools gvimdiff, meld, tkdiff, kdiff3, and kompare are used to compare text files on Linux
        In many cases, it is difficult to visually compare the files because of the large number of differences
        This script runs the Linux gvimdiff, meld, tkdiff, kdiff3, or kompare tool on 2 files
        after preprocessing each of them with a wide variety of options
        This allows you to concentrate on the important differences, and ignore the rest

    Sample Problems and Solutions:
        Problem:     Differences in whitespace or comments or case cause mismatches
        Solution:    Use options -white or -noWhite or -comments or -case

        Problem:     Log files contain dates and times
        Solution:    Use -replaceDates

        Problem:     Files both need to be filtered using regexes, to strip out certain characters or sequences
        Solution 1:  Use -grep <regex> or -ignore <regex> to filter in or out
        Solution 2:  Use -search <regex> -replace <regex> to supply one instance of substitution and replacement
        Solution 3:  Use -replaceTable <file> to supply a file with many substitution/replacement
        Solution 4:  Use -replaceDates to remove dates and timestamps

        Problem:     Need to view your changes to a file on Perforce or SVN or GIT
        Solution:    'dif file#head' will show the differences between the head revision and the local file

        Problem: need to recursively compare directories
        Solution 1:  'dif <dir1> <dir2>' will iteratively compare pairs of files
        Solution 2:  'dif <dir1> <dir2> -report' will open a GUI to compare the directories
        Any preprocessing option (-comments, -white, -sort, -grep, etc) can be used when comparing directories

    Usage Examples:
        $scriptName file1 file2
        $scriptName file1 file2 -sort
        $scriptName file1 file2 -white -case
        $scriptName file1 file2 file3 -comments
        $scriptName file1 file2 -search 'foo' -replace 'bar'
        $scriptName dir1 dir2 -report

    Filtering options:    
       -comments          Remove any comments such as // or # or single-line */ /*.  Also removes trailing whitespace

                          To remove comments in other languages, use the search/replace options:
                          For example, to replace comments (marked with ';') in assembly language:
                              -search '\\s*(;.*)?\$' -replace ''

       -white             Remove blank lines and leading/trailing whitespace
                          Condense multiple whitespace to a single space
                          Remove any non-printable characters
       
       -noWhite           Remove all whitespace and non-printable characters

       -case              Convert files to lowercase before comparing
       
       -grep 'regex'      Only display lines which match the user-specified Perl regex
                          Multiple regexs can be specified, for example:  -grep '(regexA|regexB)'
                          To display lines above/below matches, see the help text for option -externalPreprocessScript

       -ignore 'regex'    Ignore any lines which match the user-specified regex
                          This is the opposite of the -grep function

       -search 'regex'    On each line, do a global regex search and replace
       -replace 'regex'   
                          For example, to replace temporary filenames such as '/tmp/foo123456/bar.log' with '/tmp/file':
                              -search '/tmp/\\S+' -replace '/tmp/file'

                          Since the search/replace terms are interpreted as regex,
                          remember to escape any parentheses
                              Exception:  if you are using regex grouping, 
                                          do not escape the parentheses
                              For example:
                                  -search '(A|B|C)'  -replace 'D'

                          Since the replace term is run through 'eval', make sure to escape any \$ dollar signs
                          Make sure to use 'single-quotes' instead of double-quotes
                          For example, to convert all spaces to newlines, use:
                              -search '\\s+'  -replace '\\n'

                          If case-insensitive search is needed, also use option -case

       -replaceTable file     Specify a two-column file which will be used for search/replace
                              The delimiter is any amount of spaces
                              Terms in the file are treated as regular expressions
                              The replace term is run through eval

       -replaceDates      Remove dates and times, for example:
                               17:36:34
                               Monday July 20 17:36:34 PDT 2020
                               Dec  3  2019
                               Jul 10 17:42
                               1970.01.01
                               1/1/1970

       -fields N          Compare only field(s) N
                          Multiple fields may be given, separated by commas (-fields N,M)
                          Field numbers start at 0
                          Fields in the input files are assumed to be separated by spaces,
                              unless the filename ends with .csv (separated by commas)
                          Example:  -fields 2
                          Example:  -fields 0,2      (fields 0 and 2)
                          Example:  -fields -1       (last field)
                          Example:  -fields 2+       (field 2 and above)
                          Example:  -fields not2+    (ignore fields 2 and above)
                          Example:  -fields not0,5+  (ignore fields 0, 5, and above)

       -fieldSeparator regex    Only needed if default field separators above are not sufficient
                                Example:  -fieldSeparator ':'
                                Example:  -fieldSeparator '[,=]' 
       
       -fieldJustify      Make all fields the same width, right-justified

       -split             Splits each line on whitespace
       
       -splitChar 'char'  Splits each line on 'char'
                          For example:  -splitChar ',' to split on comma

       -splitWords        Splits on whitespace.  Each word will be on its own line.
                          Identical to -splitChar '\\s+'
       
       -sortWords         Sort the words in each line (space delimited)

       -trim              Trims each line to $defaults{fold} characters, discarding the overflow
                          Useful when lines are very long, and the important information is near the beginning
       
       -trimChars N       Trims with specified number of characters, instead of $defaults{fold}
       
       -head              Compare only the first 10% of the file,
                            with a minimum of $MINHEAD, and a maximum of $defaults{head} lines
       
       -headLines N       Compare only the first N lines
                          If a negative number is used, ignore the first -N lines

       -tail              Compare only the last 10% of the file
                            with a minimum of $MINHEAD, and a maximum of $defaults{head} lines
       
       -tailLines N       Compare only the last N lines
                          If a negative number is used, ignore the last -N lines
       
       -yaml              Compare two yaml files, sorting the keys
       
       -json              Compare two json files, sorting the keys

       -removeDictKeys 'regex'
                          For use with yaml or json files
                          Removes all dictionary keys matching the regex

       -flatten           For use with yaml or json files
                          Flatten nested dictionary and array structures
                          To display only one flattened file:
                              $scriptName file.yml -flatten -stdout | gvim -

       -basenames         Convert path/file to file
                          This can be useful when comparing log files which contain temporary directories

       -extensions        Convert path/file.extension to .extension
       
       -removeExtensions  Convert path/file.extension to path/file

       -round 'string'    Round all numbers according to the sprintf string
                          For example -round '%0.2f'
       
       -dos2unix          Run all files through dos2unix

       -lsl               Useful when comparing previously captured output of 'ls -l'
                          Compares only names and file sizes

       -tartv             Compare tarfiles using tar -tv, and compare the names and file sizes
                          If file sizes are not desired in the comparison (names only), also use -fields 1
          
       -perlEval          The input file is a perl hashref
                          Print the keys in alphabetical order

       -perlDump          Useful when comparing previously captured output of Data::Dumper
                          filter out all SCALAR/HASH/ARRAY/REF/GLOB/CODE addresses from output of Dumpvalue,
                          since they change on every execution
                              'SPECS' => HASH(0x9880110)    becomes    'SPECS' => HASH()
                          Also works on Python object dumps:
                              <_sre.SRE_Pattern object at 0x216e600>

      
    Filtering options to target a section of the file:    

       -start 'regex'     Start comparing file when line matches 'regex'

                          If multiple lines matching regexes should be required to start capturing,
                          Separate the regexes with ^^
                          For example, to start capture after line matching 'abc' and then line matching 'def':
                          -start 'abc^^def'

                          By default, only the first occurrence of the start/stop sequence will be captured,
                          if multiple occurrences exist within the file

       -stop 'regex'      Stop comparing file when line matches regex
                          The last matching line will be captured, unless specified otherwise

       -startIgnoreFirstLine    This modifies the 'start' operation, so that
                                The first matching line will not be captured
       
       -stopIgnoreLastLine      This modifies the 'stop' operation, so that
                                The last matching line will not be captured
       
       -startMultiple     This modifies the 'start' operation, so that
                          multiple occurrences of the same start/stop sequence may be captured

       -start1 -stop1 -start2 -stop2
                          Similar to -start and -stop
                          The '1' and '2' refer the files
                          Enables comparing different sections within the same file,
                          or different sections within different files
                          
                          For example, to compare functions 'add' and 'subtract' within a single file:
                              $scriptName a.pm -start1 'sub add' -stop1 '^}' -start2 'sub subtract' -stop '^}'

       -function 'function_name'
                          Compare same  Python def / Perl sub / TCL proc / JavaScript function from two source files
                          Internally, this leverages the -start -stop functionality
                          This feature will also work for some C source files

       -functionSort
                          Useful when Python/Perl/TCL/JavaScript functions have been moved within a file
                          This option preprocesses each file, so that the function definitions
                          appear in alphabetical order
                          This feature will also work for some C source files

       -language <lang>   For use with -function and -functionSort
                          The language is automatically determined by inspecting the file extension and shebang
                          Use this option if those clues are not present
                          Languages are specified as extensions such as: js pl py tcl


    Preprocessing options (before filtering):
       -externalPreprocessScript <script>          
                          Run each input file through your custom preprocessing script
                          It must take input from STDIN and send output to STDOUT, similar to unix 'sort'
                          
                          Trivial example:
                              -externalPreprocessScript 'sort'

                          Example using grep to show 2 lines above and below lines matching the regex 'foo'
                              -ext 'grep -C 2 foo'
                          
                          Examples for comparing binary files:
                              -ext '/usr/bin/xxd'
                              -ext '/usr/bin/xxd -c1 -p'
                              -ext '/usr/bin/hexdump -c'
                          However, a standalone diff tool may be preferable for comparing binary files
                          For example:
                              'qdiff' by Johannes Overmann and Tong Sun
                              'colorbindiff' by Jerome Lelasseux 
                              'VBinDiff' by Christopher J. Madsen
                              'dhex'
                         
       -externalPreprocessScript2 <script>          
                          This is a variation on the same idea as -externalPreprocessScript
                          Run each input file through your custom preprocessing script
                          It must take input from its first input argument
                              and send uncompressed output to its second input argument
                          
                          Example:
                              -ext2 '/path/script.pl --options'
                              $scriptName will run this on each file:
                                  /path/script.pl <infile> <outfile> --options
       
       -externalPreprocessScript3 <script>          
                          This is a variation on the same idea as -externalPreprocessScript
                          Run each input file through your custom preprocessing script
                          It must take input from its option --in <infile>
                              and send uncompressed output to its option --out <outfile>
                          
                          Example:
                              -ext3 '/path/script.pl --options'
                              $scriptName will run this on each file:
                                  /path/script.pl --options --in <infile> --out <outfile>
                         
       -bin               Compare binary files
                          This is a shortcut for running -ext '/usr/bin/xxd'
       
       -strings           Run equivalent of Linux 'strings' command on each input file to remove binary characters

       -bcpp              Run each cpp input file through bcpp linting tool with options:  $defaults{bcpp}

       -perltidy          Run each Perl input file through perltidy linting tool with options:  $defaults{perltidy}


    Postprocessing options (after filtering):
       -sort              Run Linux 'sort' on each input file

       -uniq              Run Linux 'uniq' on each input file to eliminate duplicated adjacent lines
                          Use with -sort to eliminate all duplicates
       
       -fold              Run 'fold' on each input file with default of $defaults{fold} characters per column
                          Useful for comparing long lines, so that scrolling right is not needed within the GUI

       -foldChars N       Run 'fold' on each input file with N characters per column

       -ppOnly            Stop after creating preprocessed files


    Viewing options:
       -quiet             Do not print to screen

       -verbose           Print names and file sizes of preprocessed temporary files, before comparing

       -gui cmd           Instead of using $defaults{gui} to graphically compare the files, use a different tool
                          This supports any tool which has command line usage similar to gvimdiff
                          i.e. 'gvimdiff file1 file2'.
                          This has been tested on meld, gvimdiff, kdiff3, tkdiff, and kompare, and likely works
                          with diffmerge, diffuse, kdiff, wdiff, xxdiff, colordiff, beyond compare, etc
                          Examples:

                          -gui gvimdiff
                              Uses gvimdiff as a GUI
                          
                          -gui kdiff3
                              Uses kdiff3 as a GUI

                          -gui tkdiff
                              Uses tkdiff as a GUI

                          -gui kompare
                              Uses kompare as a GUI

                          -gui meld
                              Uses meld as a GUI
                              Note that meld does not display line numbers by default on some OS
                                  Meld / Preferences / Editor / Display / Show line numbers
                                  If the box is greyed out, install python-gtksourceview2
                          
                          -gui opendiff
                              Use the macOS FileMerge tool (requires Xcode)

                          -gui none
                              This is useful when comparing from a script
                              in an automated process such as regression testing
                              After running $scriptName, the return status will be:
                                  0 = files are equal
                                  1 = files are different
                                  $scriptName a.yml b.yml -gui none -quiet ; echo \$?
                           
                          -gui diff
                              Prints diff to stdout instead of to a GUI

                          -gui 'diff -C 1' | grep -v '^[*-]'
                              Use diff, with the options:
                                  one line of Context above and below the diff
                                  remove the line numbers of the diffs

       -diff              Shortcut for '-gui diff'


    Options to compare a large set of files:
       <dirA> <dirB>           If $scriptName is run against two directories,
                               will open GUI for each pair of mismatching files
                               For example:
                                   $scriptName dirA dirB
                          
                               Any of the preprocessing options may be used
     
      -report                  When used with two directories  or  -dir2 <dir>  or  -gold
                               Instead of opening GUIs for each file pair,
                               generate report of mismatching or missing files
                               For example:
                                   $scriptName dirA dirB -report
                               Any of the preprocessing options may be used

                               It can also be used to print a simple report of
                               file sizes, number of lines, and md5sums (not a comparison)
                               For example:
                                   $scriptName * -report
                                       or
                                   $scriptName */file -report
                                       or
                                   $scriptName dir -report

      -filePairs               Similar to -report, but only displays the files which are found in both directories, and mismatch

      -filePairsWithOptions    Similar to -filePairs, but also lists the $scriptName command and options
      
      -intersection            When used with -report, only list files which exist in both directories

      -fast                    When used with -report, use only the file size to compare, instead of md5sum
                               This is much faster, but could miss cases where bits are flipped

      -includeFiles <regex>  
      -excludeFiles <regex>    Both options are for use with two directories  or  -dir2 <dir>  or  -gold
                               For example:
                                   $scriptName -includeFiles '*log' dirA dirB
                               Will open GUI for each pair of mismatching files

                               When used with -dir2 or -gold,
                               finds files in the current directory matching the Perl regex
                               For example:
                                   $scriptName -includeFiles '*log' -dir2 ../old

                               Any of the preprocessing options may be used

       -dir2 <dir>             For each input file specified, run '$scriptName'
                                   on the file in the current directory
                                   against the file in the specified directory
                               For example:
                                   cd to the directory containing the files
                                   $scriptName file1 file2 file3 -dir ../old
                               will run:
                                   $scriptName file1 ../old/file1
                                   $scriptName file2 ../old/file2
                                   $scriptName file3 ../old/file3
                               Any of the preprocessing options may be used

       -gold                   When used with one filename (file or file.extension),
                               assumes that 1st file will be (file.golden or file.golden.extension)
                             
                               For example:
                                   $scriptName file1 -gold
                               will run:
                                   $scriptName file1.golden file1.csv
                    
                               For example:
                                   $scriptName file1.csv -gold
                               will run:
                                   $scriptName file1.csv.golden file1.csv
                    
                               When used with multiple filenames
                               it runs $scriptName multiple times, once for each of the pairs
                               This option is useful when doing regressions against golden files
                             
                               For example:
                                   $scriptName file1 file2.csv -gold
                               will run:
                                   $scriptName file1.golden file1
                                   $scriptName file2.csv.golden file2.csv
                             
                               Any of the preprocessing options may be used
       
      -tree <dir1> <dir2>      Special case.  Run unix 'tree' on each of the directories.  Does not preprocess files
    
    Other options:
       -stdin             Parse input from stdin and send output to stdout
                          For example:
                              grep foo bar | $scriptName -stdin <options> | script2 | script3
                          $scriptName can autodetect piping, so this can be shortened to: 
                              grep foo bar | $scriptName <options> | script2 | script3

       -stdout            Cat all preprocessed files to stdout
                          In this use case, $scriptName could be called on only one file
                          This allows $scriptName to be part of a pipeline
                          For example:
                              $scriptName file -stdout <options> | another_script
                          If -stdin is given, then -stdout is assumed

       -in <file>         Specify input file(s)
                          This is simply an alternate syntax to the normal use case
                          $scriptName file1 file2
                          $scriptName -in file1 -in file2

       -out <file>        Similar to -stdout, but send output to file
                          This can be useful if $scriptName is used as a preprocessing engine
                          $scriptName -in infile -out outfile
       
       -filename          Intended for use with option -stdout or -out
                          At the beginning of each line, prepend the filename
                          This is similar to the grep --with-filename option
                          Useful when searching through a large set of files

       -tee <file>        Useful in combination with the -diff option
                          In addition to printing -diff output to screen, also send it to file
       
       -keeptmp           Default behavior is to remove the tmp directory containing preprocessed files
                          This option keeps it


    Other features:
        Automatically uncompresses files from these formats into intermediate files:
            .gz
            .bz2
            .xz
            .Z
            .zip  (single files only)

        Compare remote files:
            $scriptName localfile host:/path/file
            $scriptName host1:/path/file host2:/path/file
            As a prerequisite, 'scp' must already be working on the command line
            Google 'ssh-copy-id' for details on setup
        
        Compares values inside .xls|.xlsm|.xlsx files
            requires the Perl Spreadsheet::BasicRead, Spreadsheet::ParseExcel, and Spreadsheet::XLSX modules to be installed
        
        Compares values inside .ods OpenOffice spreadsheet files  
            requires the Perl Spreadsheet::Read and Spreadsheet::ParseODS module to be installed
        
        Attempts to compare text inside .pdf files
            requires the Perl CAM::PDF module to be installed
        
           

    Default compare tool:
        The default compare GUI is meld
        To change this, create the text file ~/.$scriptName.defaults with one of these content lines:
            gui: gvimdiff
            gui: tkdiff
            gui: kdiff3
            gui: kompare
            gui: meld
            gui: tkdiff
        You may also want to change the default (uncompressed) file size limit, before gvimdiff takes over from kompare/meld
        The default is $defaults{meldSizeLimit} bytes
            meldSizeLimit: 1000000


    For convenience, link to this code from ~/bin
        ln -s /path/$scriptName ~/bin/$scriptName

    ";

    my $p4usage = "
    Perforce or SVN version control support:
            Perforce uses '#' to signify version numbers.  dif borrows the same notation for SVN
    Perforce or SVN examples:
            $scriptName file              compares head version with local version (shortcut)
            $scriptName file#h            compares head version with local version (shortcut)
            $scriptName file file#head    compares head version with local version
            $scriptName file#-            compares previous version with local (shortcut)
            $scriptName file#7            compares version 7 with local version (shortcut)
            $scriptName file#6 file#7     compares version 6 with version 7
            $scriptName file#6 file#+     compares version 6 with version 7
            $scriptName file#6 file#-     compares version 6 with version 5
            $scriptName file#6..#9        compares version 6 with version 7, and then compares 7 with 8, then 8 with 9
    Git example:
            $scriptName file              compares committed version to local version

    ";

    my $backgroundPurpose = "
The graphical compare tools meld, gvimdiff, kdiff3, tkdiff, and kompare are used to compare text files on Linux

In many cases, it is difficult and time-consuming to visually compare large files because of formatting differences

For example:
* different versions of code may differ only in comments or whitespace
* log files are often many MB of unbroken text, with some \"don't care\" information such as timestamps or temporary filenames
* json or yaml files may have ordering differences


## Purpose

'$scriptName' preprocesses input text files with a wide variety of options

Afterwards, it runs the Linux tools meld, gvimdiff, kdiff3, tkdiff, or kompare on these intermediate files

'$scriptName' can also be used as part of an automated testing framework, returning 0 for identical, and 1 for mismatch";

    my $installationInstructions = "
## Installation

No installation is needed, just copy the 'dif' executable

To run the tests:
* download dif from GitHub  'git clone https://github.com/koknat/dif.git'
* cd $scriptName/test
* ./$scriptName.t
* This will run dif on the example* unit tests
* It should return with 'all tests passed'
* Perl versions 5.6.1 through 5.30 have been tested

For convenience, copy the dif executable to your ~/bin directory, or create an alias:
    alias dif /path/dif/dif

To see usage:
* cd ..  (back into $scriptName main directory)
* ./$scriptName

To run $scriptName
* ./$scriptName file1 file2 <options>
    ";

    say "$backgroundPurpose\n\n$installationInstructions" and exit if $opt{installationInstructions};    # for README.txt and README.md
    say "\n$usage";
    say "$p4usage" if whichCommand('p4');
    say "\n";
}

# Program flow:
#   The program flows linearly from top to bottom
# 	Handle ~/.dif.options and ~/.dif.defaults
# 	Parse input arguments, create @files
# 	Handle special case of -includeFiles <regex> with -dir2 or -gold, search one dir to populate @files
# 	Determine which GUI to use for comparison, and determine any decompression
# 	Handle options -search -replace -replaceDates -replaceTable
# 	if (-gold or -dir2 or -includeFiles <regex>) and not -report:
# 		if single file:
# 			determine pair of files and continue
# 		else (multiple files):
# 			spawn multiple additional dif processes
# 	Handle p4/svn/git
# 	Test for existence of files
# 	Handle options -tree & -tartv
# 	if -report and (-gold or -dir2 or -includeFiles <regex> dirA dirB):
# 		determine @filePairs
# 		preprocess each pair of files (if verbose then print results immediately)
# 		print the results and exit
# 	for my $f (@files):
# 		preprocessFile
# 	Switch to gvimdiff if processed file size is too large
# 	Run meld/gvimdiff/kdiff3/tkdiff/kompare

#$SIG{__WARN__} = sub { die @_ };  # die instead of produce warnings

# Debugger from CPAN
sub D  { say "Debug::Statements has been disabled to improve performance" }
sub d  { }
sub ls { }
#use lib "/home/ate/scripts/regression";
#use Debug::Statements ":all";  # d ''

# Surround all arguments with '', except for options such as -grep
my $originalCmdLine = "$0 " . "'" . join( "' '", @ARGV ) . "'";
$originalCmdLine =~ s/'(-\S+)'/$1/g;
d '$originalCmdLine';

# Parse options
%opt = (
    # Preprocess
    bcpp                      => '',
    perltidy                  => '',
    externalPreprocessScript  => '',
    externalPreprocessScript2 => '',
    externalPreprocessScript3 => '',
    # Postprocess
    sort      => "",
    uniq      => "",
    dos2unix  => "",
    strings   => "",
    fold      => "",
    foldChars => 0,
    trim      => "",
    trimChars => 0,
    head      => 0,
    headLines => 0,
    tail      => 0,
    tailLines => 0,
    # Filter
    ppOnly   => 0,
    white    => 0,
    noWhite  => 0,
    case     => 0,
    comments => 0,
    lsl      => 0,
    perlDump => 0,
    perlEval => 0,
    yaml     => 0,
    json     => 0,
    rp       => 0,
    # Other
    dir2     => '',
    keeptmp  => 0,
    gold     => 0,
    report   => 0,
    help     => 0,
    quiet    => 0,
    gui      => undef,
    difftool => undef,
    diff     => 0,
    gvimdiff => 0,
    tkdiff   => 0,
    kompare  => 0,
    meld     => 0,
    stdout   => 0,
);
my $d = 0;

# Parse user config files ~/.dif.options ~/.dif.defaults ~/.dif.fileMappings
#     ~/.dif.options  (same names as command line options)
#         verbose: 1
#     ~/.dif.defaults  (see available defaults at top of script)
#         gui: kompare
#         bcpp: /home/ckoknat/cs2/linux/bcpp -s -bcl -tbcl -ylcnc
#     ~/.dif.fileMappings  (enables shortcuts for commonly used names)
#         {
#             CPN => 'CheckPatternName.pm',
#             cpn => 'check_pattern_names.pl',
#         }
for my $type ( 'options', 'defaults' ) {
    d '$type';
    my $userConfigFile = "$ENV{HOME}/.$scriptName.$type";
    d '$userConfigFile';
    if ( -e $userConfigFile ) {
        d '%opt %defaults';
        my $map = readTableFile( $userConfigFile, 0, 1 );
        d '$map';
        while ( my ( $key, $value ) = each %$map ) {
            d '$key $value';
            $key =~ s/:$//;
            if ( $type eq 'options' ) {
                $opt{$key} = $value;
            } elsif ( $type eq 'defaults' ) {
                $defaults{$key} = $value;
            }
        }
    }
}
d '%opt %defaults';
my %customFilenameMappings;
for my $type ('fileMappings') {
    d '$type';
    my $userConfigFile = "$ENV{HOME}/.$scriptName.$type";
    if ( -e $userConfigFile ) {
        d "Reading $userConfigFile";
        open my $fh, '<', $userConfigFile;
        local $/;    # slurp mode;
        my $data = <$fh>;
        close $fh;
        d '$data';
        my $config;
        eval "\$config = $data";
        d '$config';

        while ( my ( $key, $value ) = each %$config ) {
            d '$key $value';
            if ( $type eq 'fileMappings' ) {
                $customFilenameMappings{$key} = $value;
            }
        }
    }
}
#d '%customFilenameMappings';
my $pwd = Cwd::cwd();
if ( $defaults{history} ) {
    #if ( $pwd =~ m{/dif/test} ) {}  # all unit tests were still triggering it
    if ( $0 =~ m{$scriptName/$scriptName.pl} ) {
        # do nothing, do not want unit tests in history
        # if this is not agreeable, another idea is to check if filenames are /^example_/ but would need to move this code below GetOpt
    } else {
        chomp( my $date = `date` );
        #my @options = sort keys %opt;  # no, don't want the default options
        my @options = sort grep /-\S+/, @ARGV;
        `echo "$date    @options" >> ~/.$scriptName.history`;
    }
}

# Options can be overridden with user config file ~/.dif.options  (key/value format)
my $valid = Getopt::Long::GetOptions( \%opt, 'd' => sub { $d = 1 }, 'dd' => sub { $d = 2 }, 'help|h|?', 'sort', 'paragraphSort', 'sortWords', 'uniq|u', 'strings', 'fold|f', 'foldChars=s', 'trim', 'trimChars=s', 'head', 'headLines=s', 'tail|t', 'tailLines=s', 'fields=s' => \@{ $opt{fields} }, 'fieldSeparator=s', 'fieldJustify', 'length', 'ppOnly', 'white|w', 'noWhite', 'case|i', 'comments|c', 'grep=s' => \@{ $opt{grep} }, 'filename', 'ignore=s' => \@{ $opt{ignore} }, 'search=s', 'replace=s', 'start=s', 'stop=s', 'start1=s', 'stop1=s', 'start2=s', 'stop2=s', 'startMultiple', 'startIgnoreFirstLine', 'stopIgnoreLastLine', 'function|func=s' => \@{ $opt{function} }, 'functionSort', 'language=s', 'replaceTable=s', 'replaceDates', 'dos2unix', 'round=s', 'basenames', 'extensions', 'removeExtensions', 'split', 'splitChar=s', 'splitWords', 'lsl', 'bcpp', 'perltidy', 'bin|binary', 'externalPreprocessScript|externalPreprocessScript1|ext|ext1|e|e1=s', 'externalPreprocessScript2|ext2|e2=s', 'externalPreprocessScript3|ext3|e3=s', 'perlDump', 'perlEval', 'xlsSheetName=s', 'yaml|yml', 'json', 'removeDictKeys=s' => \@{ $opt{removeDictKeys} }, 'flatten', 'silent', 'quiet|q', 'verbose|v', 'gui=s', 'difftool=s', 'diff', 'gvimdiff|gv', 'tkdiff', 'kdiff3', 'kompare|k', 'meld|m', 'tee=s', 'stdin', 'stdout|s', 'out=s', 'in=s' => \@{ $opt{in} }, 'rp', 'ps', 'keeptmp', 'gold|g', 'dir2=s', 'report|r', 'intersection', 'filePairs', 'filePairsWithOptions', 'fast', 'includeFiles=s' => \@{ $opt{includeFiles} }, 'excludeFiles=s' => \@{ $opt{excludeFiles} }, 'recursive=s', 'noDirs', 'missingFileDummy', 'hash=s', 'tree', 'tartv', 'noBackgroundProcess', 'installationInstructions' );
if ( !$valid ) {
    # If an invalid option is used, GetOptions will print "Unknown option: <option>"
    usage();
    exit 1;
}
# noDirs is not in usage.  It excludes directories
$opt{quiet} = 1 if $opt{silent};                                                                # for backwards compatibility of -silent
die "\nERROR:  -recursive <regex> is now called -includeFiles <regex>\n" if $opt{recursive};    # cannot handle this easily, because it needs to spawn more 'dif' processes

my ( $globaltmpdir, %getHash );
my $cleanup = $opt{keeptmp} ? 0 : 1;
my $macOS   = ( $^O =~ /darwin/i ) ? 1 : 0;                                                     # Are we running on MacOS?
my $windows = ( $^O =~ /Win/ )     ? 1 : 0;                                                     # Are we running on Windows?
if ($windows) {
    $globaltmpdir = tempdir( 'C:\Windows\Temp\d_XXXX', CLEANUP => $cleanup );
} else {
    # keep the directory name relatively short because it appears on top of the gui window
    $globaltmpdir = tempdir( '/tmp/d_XXXX', CLEANUP => $cleanup );
}

# Remove files from original command line
my @originalFiles = @ARGV;
d '$originalCmdLine';
my $commandLineWithoutFiles = $originalCmdLine;
for my $file (@originalFiles) {
    $commandLineWithoutFiles =~ s/'$file'/ /;
}
$commandLineWithoutFiles =~ s/\s+/ /g;
d '$commandLineWithoutFiles';

# Check if files exist
my @files = @ARGV;
push @files, @{ $opt{in} };
#d '@files';die;
die "ERROR:  Directory $opt{dir2} not found!\n" if $opt{dir2} and !-d $opt{dir2};    # TODO move this earlier

# Handle multiple -fields -grep -ignore -function -includeFiles -excludeFiles -removeDictKeys
$opt{fields} = join ',', @{ $opt{fields} };
delete $opt{fields} if $opt{fields} eq '';
$opt{grep} = join '|', @{ $opt{grep} };
delete $opt{grep} if $opt{grep} eq '';
$opt{ignore} = join '|', @{ $opt{ignore} };
delete $opt{ignore} if $opt{ignore} eq '';
$opt{function} = join '|', @{ $opt{function} };
delete $opt{function} if $opt{function} eq '';
$opt{includeFiles} = join '|', @{ $opt{includeFiles} };
delete $opt{includeFiles} if $opt{includeFiles} eq '';
$opt{excludeFiles} = join '|', @{ $opt{excludeFiles} };
delete $opt{excludeFiles} if $opt{excludeFiles} eq '';
$opt{removeDictKeys} = join '|', @{ $opt{removeDictKeys} };
delete $opt{removeDictKeys} if $opt{removeDictKeys} eq '';

if ( !-t and !@files ) {
    # https://stackoverflow.com/questions/18991832/how-to-tell-if-my-program-is-being-piped-to-another-perl
    $opt{stdin} = 1;
}
if ( $opt{stdin} ) {
    $opt{stdout} = 1 unless defined $opt{out};
    my $content = do { local $/; <STDIN> };
    my $tmpfile = determineTmpFilename( 'stdin', 1 );
    open( my $TMP, '>', $tmpfile ) or die "ERROR: Cannot open file for writing:  $tmpfile\n\n";
    print $TMP $content;
    close $TMP;
    $files[0] = $tmpfile;
}
if ( defined $opt{excludeFiles} and !defined $opt{includeFiles} ) {
    $opt{includeFiles} = '.';
}
if ( $opt{dir2} and !defined $files[0] and !defined $opt{includeFiles} ) {
    $opt{includeFiles} = '.';
}
if ( defined $opt{includeFiles} ) {
    if ( $opt{dir2} or $opt{gold} ) {
        # -includeFiles with -dir2 or -gold
        # To test this:
        #     cd test/dirA
        #     dif.pl -includeFiles 'case01[ac]' -dir2 ../dirA    (passes)
        #     dif.pl -includeFiles 'case01[ac]' -dir2 ../dirB    (fails)
        push @files, runFileFind( '.', $opt{includeFiles}, $opt{excludeFiles} );
    } elsif ( -d $files[0] and -d $files[1] ) {
        # -includeFiles <regex> with dirA dirB
        # do nothing
    } elsif ( -f $files[0] and !-f $files[1] ) {
        # -includeFiles <regex> with dirA dirB
        say "WARNING:  File does not exist:  $files[1]";
        exit 1;
    } elsif ( !-f $files[0] and -f $files[1] ) {
        # -includeFiles <regex> with dirA dirB
        say "WARNING:  File does not exist:  $files[0]";
        exit 1;
    } elsif ( -f $files[0] and -f $files[1] ) {
        # -includeFiles <regex> with dirA dirB
        # do nothing
    } else {
        say "ERROR:  option -includeFiles <regex> or -excludeFiles <regex> must be used with either -dir2 or -gold or a pair of directories";
        exit 1;
    }
}
#die "\@files = @files";
if ( $opt{help} or $opt{installationInstructions} ) {
    usage();
    say "Exiting because of -help";
    exit 0;
}
if ( !@files ) {
    usage();
    say "\nNo files were specified:    $originalCmdLine\n\n";
    exit 0;    # Exit 0 so that compilation test passes
}
$files[0] .= 'ead' if $files[0] =~ /#h$/;    # enable #h instead of #head
$files[1] .= 'ead' if $files[0] =~ /#h$/;    # enable #h instead of #head
d '%opt @files';
# To use with Windows, download http://strawberryperl.com and WinMerge.  Windows support is very limited, expect many features to not work, and prepare to do your own development

# Handle custom file mappings from ~/.dif.fileMappings
my ( $p4rev, $filePrefix );
if ( $files[0] =~ /(#.*)/ ) {
    ( $filePrefix = $files[0] ) =~ s/(#.*)//;
    $p4rev = $1;
} else {
    $filePrefix = $files[0];
    $p4rev      = '#head';
}
d '$p4rev $filePrefix';
#d '%customFilenameMappings $customFilenameMappings{$filePrefix}';
if ( defined $filePrefix and defined $customFilenameMappings{$filePrefix} ) {
    $files[0] = "$customFilenameMappings{$filePrefix}$p4rev";
}
d '@files';

# Determine which diff tool to use
# Start with $defaults{gui}, which is hard-coded or in ~/.dif.defaults
# Next look at options -diff -gvimdiff -kompare -meld  -gui <tool>
my $atHome = -d '/home/ckoknat' ? 1 : 0;
my $gui = $defaults{gui};
if ( $opt{diff} ) {
    $gui = 'diff';
} elsif ( $opt{gvimdiff} ) {
    $gui = 'gvimdiff';
} elsif ( $opt{tkdiff} ) {
    if ( -e '/home/utils/tkdiff-4.2/bin/tkdiff' ) {
        $gui = '/home/utils/tkdiff-4.2/bin/tkdiff';
    } else {
        $gui = 'tkdiff';
    }
} elsif ( $opt{kompare} ) {
    $gui = 'kompare';
} elsif ( $opt{kdiff3} ) {
    $gui = 'kdiff3';
} elsif ( $opt{meld} ) {
    $gui = 'meld';
} elsif ( defined $opt{difftool} ) {    # Renamed to -gui, but retained for backwards compatibility for Amit
    $gui = $opt{difftool};
} elsif ( defined $opt{gui} ) {
    $gui = $opt{gui};
    $gui = 'none' if $gui eq '';
} else {
    # do nothing, stay with default
}
d '$gui';

if ( $gui eq 'meld' ) {
    my $meld      = whichCommand('meld');
    my $meld_161  = "/home/utils/meld-1.6.1/bin/meld";
    my $meld_186  = "/home/utils/meld-1.8.6-2/bin/meld";
    my $meld_3163 = "/home/utils/meld-3.16.3/bin/meld";
    if ( defined $meld and -f $meld ) {
        # use default location of meld
    } elsif ( -f '/usr/bin/meld' ) {
        $meld = '/usr/bin/meld';
    } elsif ( -f $meld_3163 ) {
        $meld = $meld_3163;
    } elsif ( -f $meld_186 ) {
        $meld = $meld_186;
    } elsif ( -f $meld_161 ) {
        $meld = $meld_161;
    } else {
        say "WARNING:  meld not found.  Using gvimdiff instead" unless $opt{quiet};
        $meld = 'gvimdiff';
    }
    $gui = $meld;
}
d '$gui';
# Fall back to gvimdiff if gui is not installed
if ( $gui ne 'none' ) {
    my $newGui = whichCommand( $gui, 'meld', 'gvimdiff', 'vim -d', 'kompare', 'tkdiff' );
    if ( defined $newGui ) {
        if ( $newGui ne $gui ) {
            say "Using '$newGui' since '$gui' is not installed" unless $opt{quiet};
            $gui = $newGui;
        }
    } else {
        die "ERROR:  Could not find a compare gui on this OS, such as 'meld', 'gvimdiff', or 'vim -d'";
    }
}
if ($windows) {
    #$gui = "fc.exe";  # like diff
    $gui = "start WinMerge";    # Need to install from internet
}

if ( $opt{filePairs} ) {
    $opt{report} = 1;
    $opt{stdout} = 1 unless defined $opt{out};
} elsif ( $opt{filePairsWithOptions} ) {
    $opt{report} = 1;
    $opt{stdout} = 1 unless defined $opt{out};
} else {
    # do nothing
}

$opt{splitChar} = '\s+' if $opt{splitWords};
if ( $opt{split} or defined $opt{splitChar} ) {
    if ( defined $opt{search} or $opt{replace} ) {
        say "ERROR:  Cannot use -search/-replace with -split or -splitChar";
        exit 1;
    } elsif ( $opt{split} ) {
        $opt{search}  = "\\s+";
        $opt{replace} = "\\n";
    } elsif ( defined $opt{splitChar} ) {
        #$opt{search} = quotemeta( $opt{splitChar} );  # Screws up -splitChar '\s+'
        $opt{search}  = "$opt{splitChar}";
        $opt{replace} = "\\n";
    } else {
        die "Program bug";
    }
}

$opt{start} = $opt{start2} if defined $opt{start2};
$opt{stop}  = $opt{stop2}  if defined $opt{stop2};
$opt{start} = $opt{start1} if defined $opt{start1};
$opt{stop}  = $opt{stop1}  if defined $opt{stop1};
if ( not $files[1] and $opt{start2} ) {
    $files[1] = $files[0];
}
d '@files';

if ( $opt{function} ) {
    if ( $opt{start} or $opt{stop} ) {
        say "ERROR:  Cannot use -function with -start or -stop";
        exit 1;
    }
    # def quickSort(a):
    # sub usage
    # proc getMd5sum
    my $functionStartRegex;
    my $language = defined $opt{language} ? $opt{language} : getScriptType( file => $files[0] );
    if ( $language =~ /^(php|pl|tcl|js)$/ ) {
        $functionStartRegex = '\s*(sub|proc|function)\b';                    #### function may require changing filetype regex
        $opt{start}         = "^$functionStartRegex\\s+$opt{function}\\b";
        $opt{stop}          = "^($functionStartRegex|})";                    # '}' (Perl sub, TCL proc)  or  start of next sub (Perl sub, TCL proc, Python def)
    } elsif ( $language eq 'py' ) {
        $functionStartRegex = '\s*def\b';
        $opt{start}         = "^$functionStartRegex\\s+$opt{function}\\b";
        $opt{stop}          = "^($functionStartRegex|\\s*\$)";               # '}' (Perl sub, TCL proc)  or  start of next sub (Perl sub, TCL proc, Python def)
    } else {
        $functionStartRegex = '\s*(unsigned\s+|signed\s+)?(sub|proc|def|function|func|fun|fn|void|int|char|short|long|float|double|size_t|string|vector|unsigned|istream|ostream)';
        $opt{start}         = "\\s*$functionStartRegex\\s+$opt{function}\\b";
        $opt{stop}          = '^\s*((unsigned\s+|signed\s+)?(sub|proc|def|function|func|fun|fn|void|int|char|short|long|float|double|size_t|string|vector|istream|ostream)\s+([^\s;]+)|})\s*$';
    }
    $opt{startMultiple} = 1;
    if ( $files[0] =~ /\.py$/ ) {
        $opt{stopIgnoreLastLine} = 1;
    }
}

# Decide if file needs to go through the preprocessing code
# If not, then we can later do a quick md5sum check to determine equality
my $preprocessOptions = 0;
$preprocessOptions = 1 if $opt{sort} or $opt{paragraphSort} or $opt{sortWords} or $opt{uniq} or $opt{strings} or $opt{fold} or $opt{foldChars} or $opt{trim} or $opt{trimChars} or $opt{head} or $opt{headLines} or $opt{tail} or $opt{tailLines} or defined $opt{fields} or $opt{fieldJustify} or $opt{length} or $opt{white} or $opt{noWhite} or $opt{case} or $opt{comments} or defined $opt{round} or $opt{basenames} or $opt{extensions} or $opt{removeExtensions} or $opt{dos2unix} or defined $opt{grep} or defined $opt{filename} or defined $opt{ignore} or defined $opt{start} or defined $opt{stop} or defined $opt{search} or defined $opt{replace} or $opt{replaceTable} or $opt{replaceDates} or $opt{functionSort} or $opt{lsl} or $opt{perltidy} or $opt{bin} or $opt{externalPreprocessScript} or $opt{externalPreprocessScript2} or $opt{externalPreprocessScript3} or $opt{perlEval} or $opt{yaml} or $opt{json} or defined $opt{removeDictKeys} or $opt{flatten} or $opt{bcpp} or $opt{perlDump} or $opt{rp} or $opt{ps};
my $preprocessRequired = $preprocessOptions;
d '$preprocessRequired';
my $tarPP = '';
for my $file (@files) {
    if ( $file =~ /\.tar(\.gz|bz2|xz|Z|zip)?(#(\d+|head|\-|\+))?$/ ) {
        my ( $compression, $p4 ) = ( $1, $2 );
        if ( $opt{tartv} or $opt{externalPreprocessScript} or $opt{externalPreprocessScript2} or $opt{externalPreprocessScript3} ) {
            # do nothing, will be handled later
        } elsif ( $opt{bin} ) {
            # do nothing, provide raw data to xxd
        } else {
            d "strings preprocessing required because of .tar";
            say "Turning on option -strings and using gvimdiff because of binary content in .tar file" unless $opt{quiet};
            $opt{strings} = 1;
            if ( defined $compression ) {
                $tarPP = 'tar -tvz';
            } else {
                $tarPP = 'tar -tv';
            }
            $preprocessRequired = 1;
            $gui = 'gvimdiff' unless $gui =~ /^(diff|none)$/;
        }
    }
    if ( $opt{bin} ) {
        # do nothing, provide raw data to xxd
    } elsif ( $file =~ /\.gz$/ ) {
        if ( $gui =~ /^(diff|kompare|kdiff3|meld)$/ ) {
            d "preprocessing required because of .gz and GUI";
            $preprocessRequired = 1;
        } elsif ( $gui eq 'none' ) {
            d "preprocessing required because of .gz and no GUI";
            $preprocessRequired = 1;
        }    # Avoids "binary files differ"
    } elsif ( $file =~ /\.(bz2|xz|Z|zip|ods|pdf|xls[mx]?)$/ ) {
        d "preprocessing required because of other compression";
        $preprocessRequired = 1;
        # TODO check if uncompress is really required with the various GUIs
    } else {
        # do nothing
    }
}
if ( $gui =~ /^(gvim|gvimdiff)/ and $preprocessRequired ) {
    # Set gvim options to speed up comparison
    # Only for preprocessed files, since the options will prevent reading of compressed files
    # gvimdiff can natively display .gz files
    $gui =~ s/^(gvim(diff)?)/$1 -u NONE -U NONE -N -R +"set number" +"set ic" +"set hlsearch"/;
}
if ( $gui =~ /^(gvim|gvimdiff)/ ) {
    $defaults{fold} = 80;    # columns used by -fold, gvimdiff uses larger font than kompare
}
d '$preprocessRequired';

# Setup for uncompression
my @zipExtension = @files;
for my $f (@zipExtension) {
    $f =~ s/^.*\././;
    $f =~ s/^.*(\.(gz|bz2|xz|Z|zip))$/$1/;
    $f = '.gz' if !defined $f;    # .gz zdiff is the default since it handles uncompressed files
}
$zipExtension[1] = $zipExtension[0] if !defined $zipExtension[1];    # perforce#NNN without 2nd file
d '@files @zipExtension';
my $zipDiff;
if ( grep { /\.xz/ } @zipExtension ) {
    # Due to bug in xzdiff, which returns status 0 regardless if files differ or not, require preprocessing (unzipping)
    $preprocessRequired = 1;
    $zipDiff            = 'zdiff';
} elsif (
    grep {
        /\.zip/
    } @zipExtension
  )
{
    # There is no zdiff type of tool for zip
    $preprocessRequired = 1;
    $zipDiff            = 'zdiff';    # zdiff handles uncompressed files.  The preprocessing will unzip them
} elsif ( $zipExtension[0] eq $zipExtension[1] ) {
    my %diffref = ( '.gz' => 'zdiff', '.bz2' => 'bzdiff', '.xz' => 'xzdiff', '.Z' => 'uncompress' );
    $zipDiff = $diffref{ $zipExtension[0] };
    $zipDiff = 'diff' if !$zipDiff;            # .txt
                                               #$zipDiff = 'zdiff' if !$zipDiff;    # .txt
} else {
    # Files have different zip formats
    $preprocessRequired = 1;
    $zipDiff            = 'zdiff';
}
d '$zipDiff $preprocessRequired';
$zipDiff = 'diff' if $macOS;                   # zdiff doesn't work on MacOS "/usr/bin/zdiff: line 49: setvar: command not found" (at least in Catalina)

my ( $head, $tail );
$opt{quiet} = 1 if $opt{stdout} or defined $opt{out};
if ( $opt{headLines} ) {
    $head = $opt{headLines};
} elsif ( $opt{head} ) {
    my $zipCat     = extension2zipcat( $files[0] );
    my $numLines   = getNumLines("$zipCat '$files[0]'");
    my $tenPercent = $numLines / 10;
    if ( $tenPercent < $MINHEAD ) {
        $head = $MINHEAD;
    } elsif ( $tenPercent < $defaults{head} ) {
        $head = $tenPercent;
    } else {
        $head = $defaults{head};
    }
} else {
    $head = $MAXHEAD;
}
if ( $opt{tailLines} ) {
    $tail = $opt{tailLines};
} elsif ( $opt{tail} ) {
    my $zipCat     = extension2zipcat( $files[0] );
    my $numLines   = getNumLines("$zipCat '$files[0]'");
    my $tenPercent = $numLines / 10;
    if ( $tenPercent < $MINHEAD ) {
        $tail = $MINHEAD;
    } elsif ( ($numLines) / 10 < $defaults{head} ) {
        $tail = $numLines / 10;
    } else {
        $tail = $defaults{head};
    }
} else {
    $tail = $MAXHEAD;
}
$opt{dos2unix} = "| dos2unix" if $opt{dos2unix} ne "" and whichCommand('dos2unix');
$opt{sort} = "| sort" if $opt{sort} ne "";
$opt{sort} = "| perl -n00 -e 'push \@a, \$_; END { print sort \@a }'" if $opt{paragraphSort};
$opt{uniq} = "| uniq" if $opt{uniq} ne "" and whichCommand('uniq');

if ( $opt{strings} ne "" ) {
    if ( whichCommand('strings') and !$macOS ) {
        $opt{strings} = "strings";
    } else {
        # Use perl if 'strings' executable does not exist in Linux.  This is somewhat slower, and not exactly the same output
        $opt{strings} = "perl -nle 'print \$& while m/[[:print:]]{4,}/g'";
    }
}
if ( $opt{fold} or $opt{foldChars} ) {
    $opt{fold} = $opt{foldChars} ? "| fold -s -w $opt{foldChars}" : "| fold -s -w $defaults{fold}";
}
if ( $opt{trim} or $opt{trimChars} ) {
    $opt{trim} = $opt{trimChars} ? $opt{trimChars} : $defaults{fold};
}
if ( ( defined $opt{removeDictKeys} or $opt{flatten} ) and ( !$opt{yaml} and !$opt{json} ) ) {
    if ( getFileType( $files[0] ) eq 'yml' ) {
        $opt{yaml} = 1;
    } elsif ( getFileType( $files[0] ) eq 'json' ) {
        $opt{json} = 1;
    }
}
d "after getFileType (1)";

my $fieldsNegate = 0;
if ( defined $opt{fields} ) {
    if ( $opt{fields} =~ s/^\!// ) {
        # The '!' gets interpreted by the shell on the command line
        $fieldsNegate = 1;
    }
    if ( $opt{fields} =~ s/^not// ) {
        # workaround for above problem
        $fieldsNegate = 1;
    }
}

# -search -replace and -replaceTable and -replaceDates
my ( $replaceTable_ref, @sub_keys_ordered );
$opt{replaceTable} = "/home/ckoknat/s/regression/rp/ktable.txt" if $opt{rp};    # work-specific
$opt{replaceTable} = "/home/ckoknat/s/regression/ps_ktable.txt" if $opt{ps};    # work-specific
if ( $opt{search} or $opt{replace} or $opt{replaceTable} or $opt{replaceDates} ) {
    if ( ( defined $opt{search} and !defined $opt{replace} ) or ( !defined $opt{search} and defined $opt{replace} ) ) {
        die "Options -search and -replace must be used together";
    }
    if ( $opt{replaceTable} ) {
        $replaceTable_ref = readTableFile( $opt{replaceTable}, 0, 1 );          # readTableFile($opt{tablefile},$opt{reverse},$opt{regex})
        d '$replaceTable_ref';
        if ( !%{$replaceTable_ref} ) {
            say "ERROR:  Did not find any entries in table file!  Exiting.\n";
            exit 1;
        }
    }
    if ( defined $opt{search} or $opt{replace} ) {
        $replaceTable_ref->{ $opt{search} } = eval "qq($opt{replace})";
    }
    if ( $opt{replaceDates} ) {
        my $weekdayRegex     = qr/(Mo(n(day)?)?|Tu(e(s(day)?)?)?|We(d(nesday)?)?|Th(u(r(s(day)?)?)?)?|Fr(i(day)?)?|Sa(t(urday)?)?|Su(n(day)?)?)/;
        my $monthRegex       = qr/(Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|(Nov|Dec)(?:ember)?)/;
        my $timeRegex        = qr/\d{2}:\d{2}(:\d{2})?/;                                                                                                                     # 17:36:34
        my $timezoneRegex    = qr/([ECIMP][SD]T|GMT|UTC)/;                                                                                                                   # EST CST IST PST EDT CDT IDT PDT GMT UTC
        my $dayRegex         = qr/\d{1,2}/;
        my $yearRegex        = qr/\d{4}/;
        my $dateYMDregex     = qr<\d{4,98}[/\-._]\d{1,2}[/\-._]\d{1,2}>;                                                                                                     # YYYY-MM-DD   ,99 is a kludge to make the regex longer, and therefore appear before $dateDMYregex
        my $dateDMYregex     = qr<\d{1,2}[/\-._]\d{1,2}[/\-._]\d{2,4}>;                                                                                                      # DD-MM-YYYY  DD and MM are interchangeable
        my $replaceDates_ref = {
            qr/($weekdayRegex\s+)?$monthRegex\s*$dayRegex(\s+$timeRegex)?(\s*$timezoneRegex)?(\s*$yearRegex)?/ => 'date',
            qr/$dayRegex(_|-|\s+)?$monthRegex(_|-|\s+)?$yearRegex(_|-|\s+)?($timeRegex)?/                      => 'date',                                                    # 16-Jul-2022_20:11:35
            qr/${dateYMDregex}(_|T|\s+)${timeRegex}(\+\d\d:\d\d|Z)?/                                           => 'date',                                                    # 2020-07-27T21:13:23+00:00
            qr/${dateDMYregex}(_|T|\s+)${timeRegex}(\+\d\d:\d\d|Z)?/                                           => 'date',                                                    # 2020-07-27T21:13:23+00:00
            qr/${timeRegex}/                                                                                   => 'date',                                                    # 21:13:23
            qr/\d{8}(_|T|\s+)\d{6}Z/                                                                           => 'date',                                                    # 20200727T211323Z
            $dateYMDregex                                                                                      => 'date',                                                    # 'YYYY-MM-DD'
            $dateDMYregex                                                                                      => 'date',                                                    # 'DD-MM-YYYY'
        };
        while ( my ( $search, $replace ) = each %$replaceDates_ref ) {
            $replaceTable_ref->{$search} = $replace;
        }
    }
    $opt{search_replace} = 1;
    # The longer regexes are implemented before the shorter ones
    @sub_keys_ordered = ( reverse sort { length $a <=> length $b } keys %$replaceTable_ref );
    d( '@sub_keys_ordered', 'e' );
}
d '$replaceTable_ref';

my @files_orig = @files;
if ( $opt{dir2} ) {
    $opt{noDirs} = 1;
}
if ( $opt{noDirs} ) {
    @files = ();
    for my $file (@files_orig) {
        if ( -d $file ) {
            # do nothing
        } else {
            push @files, $file;
        }
    }
}

if ( $opt{gold} and $opt{dir2} ) {
    die "ERROR:  Cannot use -gold with -dir2";
}
if ( -d $files[0] and !$opt{tree} and !defined $opt{includeFiles} ) {
    $opt{includeFiles} = '.';
    unless ( $opt{report} or $opt{quiet} ) {
        say "To generate a report of differing files, use the -report option";
    }
}
d '@files';
if ( ( $opt{gold} or $opt{dir2} or ( defined $opt{includeFiles} and -d $files[0] ) ) and !$opt{report} ) {
    # Keep in mind -gold may be used with many files, each of them having a golden version.  In this case @files contains many files.  It will then call dif recursively, this time @files will only have one file
    # When making changes to -dir2 or -gold, perform the manual test at the top of dif2.t
    if ( scalar @files == 1 ) {
        # If -gold is used, get the golden/non-golden version
        # If -dir2 is used, get the file from the other directory
        if ( $opt{gold} ) {
            my ( $goldfile, $position ) = toFromGolden( $files[0] );
            if ( $position == 1 ) {
                unshift @files, $goldfile;
            } else {
                push @files, $goldfile;
            }
            d '@files';
            say "Comparing $files[0] with $files[1]" unless $opt{quiet};
        }
        if ( $opt{dir2} ) {
            my $dir2file = toDir2( $files[0] );
            push @files, $dir2file;
            d '@files';
            say "Comparing $files[0] with $files[1]" unless $opt{quiet};
        }
    } else {
        # If more than one file was specified with -gold or -dir2, call dif multiple times with options
        #if ( -d $files[1] ) {}
        say "\nComparing each file individually.  To view a summarized report instead, use option -report" unless $opt{quiet};
        if ( $defaults{openMultipleGUIs} ) {
            say "Opening multiple GUI at once.  To change this behavior, add this inside your ~/.$scriptName.defaults file:    openMultipleGUIs: 0\n" unless $opt{quiet};
        } else {
            if ( scalar @files > 1 ) {
                say "Opening only one GUI at a time.  To change this behavior, add this inside your ~/.$scriptName.defaults file:    openMultipleGUIs: 1\n" unless $opt{quiet};
            }
        }
        d '@files';
        my @filePairs;
        if ( $opt{gold} ) {
            # dif file1 file2 file3 -gold  =>
            # dif file1 -gold
            # dif file2 -gold
            # dif file3 -gold
            @filePairs = @files;
        } elsif ( $opt{dir2} ) {
            # dif file1 file2 file3 -dir dirB  =>
            # dif file1 -dir dirB
            # dif file2 -dir dirB
            # dif file2 -dir dirB
            @filePairs = @files;
        } elsif ( $opt{includeFiles} and -d $files[0] and -d $files[1] ) {
            # dif dirA dirB  =>
            # create pairs:
            #     dirA/file1, dirB/file1, dirA/file2, dirB/file2, dirA/file3, dirB/file3
            #     "dirA/file1 dirB/file1", "dirA/file2 dirB/file2", "dirA/file3 dirB/file3"
            #     dif dirA/file1 dirB/file1
            #     dif dirA/file2 dirB/file2
            #     dif dirA/file3 dirB/file3
            my @allFilePairs = findFilePairs( $files[0], $files[1], $opt{includeFiles}, $opt{excludeFiles} );
            d '@allFilePairs';
            @filePairs = pairwise(@allFilePairs);
        } else {
            die "Program bug";
        }
        d '@filePairs';
        for my $file (@filePairs) {
            # This can lead to many windows being opened successively, with Ctrl-C not working well
            # Try one of these:
            #     minimize the GUI window and hold down Ctrl-C until you see the command prompt appear
            #     pgrep -l /home/ate/scripts/dif    and then kill the processes
            #     pkill /home/ate/scripts/dif
            my $cmd = "$commandLineWithoutFiles $file";
            # Could check if dir2 or gold file exists, before running another instance of dif
            $cmd =~ s/ -find(Files)?\s+(\S+)//;    # -includeFiles <regex> or -find <regex>
            d '$cmd';
            if ( scalar @filePairs > 1 ) {
                $cmd .= ' -missingFileDummy';
            }
            # dif normally runs the gui tool in the backgrounds 'dif file1 file2 &', so that the command line remains available
            # However, in this use case, we want dif to pause while the GUI is open.  When the user closes the GUI, move on to the next file
            if ( $ENV{DEBUG_DIF} ) {
                $cmd = "echo $cmd" if $ENV{DEBUG_DIF};
            } else {
                if ( $defaults{openMultipleGUIs} ) {
                    system "$cmd &";
                } else {
                    if ( scalar @filePairs > 1 ) {
                        $cmd .= ' -noBackgroundProcess';
                    }
                    system "$cmd";
                }
            }
            select( undef, undef, undef, 0.1 );    # Sleep for 100 ms to allow Ctrl-C to work better.  Works with any version of Perl
        }
        exit 0;
    }
}

# Perforce / SVN / GIT
my ( %scms, $scm );
my $file0dir = dirname( $files[0] );
if ( -d "$file0dir/.svn" ) {
    $scms{SVN} = 1;
    $scm = 'svn';
} elsif ( defined $ENV{P4CONFIG} or defined $ENV{P4CLIENT} ) {
    # Some inspiration taken from tkdiff 5.0 proc scm-detect
    $scms{Perforce} = 1;
    $scm = 'p4';
} else {
    chomp( my $isGit = `git rev-parse --is-inside-work-tree 2> /dev/null` );
    d '$isGit';
    if ( $isGit eq 'true' ) {
        $scms{GIT} = 1;
        $scm = 'git';
    }
}
if ( $scms{Perforce} or $scms{SVN} or $scms{GIT} ) {
    # The environment supports P4, SVN, or git
    my $foundVCSfile = 0;
    if ( not $files[1] and $files[0] =~ /^([^#\s]+)#(\d+)\.\.#?(\d+|h|head)$/ ) {
        # dif //path/file#1..#3
        # opens window for #1 vs #2, then #2 vs #3
        my ( $file, $begin, $end ) = ( $1, $2, $3 );
        d '$file $begin $end $files[0] $originalCmdLine';
        $originalCmdLine =~ s/'$files[0]'//;
        d '$originalCmdLine';
        if ( $end =~ /(h|head)/ ) {
            $end = lastScmRev($file);
        }
        if ( $opt{report} ) {
            # dif -report p4file#revA..revB
            # Useful in conjunction with -function <func> or -start <regex> -stop <regex>
            @files = ();
            my $bfile = basename($file);
            my $extension;
            if ( $bfile =~ s/\.(.*)$// ) {
                $extension = $1;
            }
            say "It may be helpful to use option -keeptmp" if !$opt{keeptmp} and !$opt{quiet};
            for my $rev ( $begin .. $end ) {
                my $tmpfile = "$globaltmpdir/${bfile}";
                $tmpfile .= "_p4_${rev}";
                $tmpfile .= ".$extension" if defined $extension;
                my $cmd = "cd $pwd ; p4 print -q $file#$rev > $tmpfile";
                system "$cmd";
                push @files, $tmpfile;
            }
        } else {
            # dif p4file#revA..revB
            # Spawn multiple processes:
            #     dif p4file #1 #n
            #     dif p4file #2 #n
            #     ...
            for my $rev ( $begin .. $end - 1 ) {
                my $cmd = "$originalCmdLine '$file#$rev' '#n' '-noBackgroundProcess'";
                d '$cmd';
                system "$cmd";
            }
            exit 0;
        }
    }

    d '@files';
    if ( -d $files[0] ) {
        # directory, do nothing
    } elsif ( not defined $files[1] and not $opt{stdout} and not defined $opt{out} and not $opt{dir2} and not $opt{gold} ) {
        if ( $files[0] =~ /^([^#\s]+)#(\d+|head|n|next|\+|\-)$/ ) {
            # If only one file was specified, and it's a perforce p4 rev, get the current non-revved version
            # dif file#123  => dif file#123 file
            # dif file#head => dif file#head file
            d 1;
            my $nonrevp4file = $1;
            say "1st file will be $files[0]"     unless $opt{quiet};
            say "2nd file will be $nonrevp4file" unless $opt{quiet};
            push @files, $nonrevp4file;
            $foundVCSfile = 1;
        } else {
            d 2;
            # If only one file was specified, compare to the head rev
            # dif file      => dif file#head file
            if ( -e $files[0] ) {
                say "1st file will be $files[0]#head" unless $opt{quiet};
                say "2nd file will be $files[0]"      unless $opt{quiet};
                $files[1]     = "$files[0]";
                $files[0]     = "$files[0]#head";
                $foundVCSfile = 1;
            }
        }
    }
    d '@files';
    # Enable  'dif file#1 #2'
    d '@files';
    my ( $lastBase, $lastRev );
    for my $filenum ( 0 .. $#files ) {
        d '.';
        d '$filenum';
        if ( $files[$filenum] =~ m{^//} ) {
            $preprocessRequired = 1;
            $foundVCSfile       = 1;
        }
        if ( $files[$filenum] =~ /(.*)#(\d+|head|n|next|\+|\-)$/ ) {
            # Handle revs of files
            # dif file#head file#-
            $preprocessRequired = 1;
            my ( $base, $rev ) = ( $1, $2 );
            d '$base $rev';
            $base = $lastBase if $base eq '';    # file#8 #n
            d '$base';
            if ( $rev =~ /^(n|next|\+)$/ ) {
                $files[$filenum] = $base . '#' . ( $lastRev + 1 );
            } elsif ( $rev =~ /^(\-)$/ ) {
                d 'minus';
                if ( !defined $lastRev or $lastRev =~ /(h|head)/ ) {
                    $lastRev = lastScmRev($base);
                    d '$lastRev';
                }
                $files[$filenum] = $base . '#' . ( $lastRev - 1 );
            } else {
                $files[$filenum] = $base . '#' . ($rev);
            }
            $lastBase = $base;
            $lastRev  = $rev;
            d '$lastRev';
            $foundVCSfile = 1;
        } elsif ( "@files" =~ /(.*)#(\d+|head|n|next|\+|\-)$/ ) {
            # dif file file#-
            $lastRev = lastScmRev( $files[$filenum] );
            d '$lastRev';
        } else {
            # do nothing to save time
        }
    }
    d '@files';
    say "Files are: @files" if $foundVCSfile and $opt{verbose};
}
d '@files';
for my $file (@files) {
    if ( $file =~ m{^\S+:/} ) {
        # host:/path/file
        $preprocessRequired = 1;
    }
}

# Test for existence of files and directories
#my @dirs;
my $ls = $windows ? 'ls' : 'ls';    # TODO need equivalent of 'ls -l' for windows
#my $numFiles = 0;
#my $numDirs = 0;
if ( $opt{report} ) {
    # do nothing
} else {
    my $count = 1;
    for my $file (@files) {
        next if $file =~ m{^//} or $file =~ /#(\d+|head|n|next|\+|\-)$/ or $file =~ m{^\S+:/};
        d "Testing for existence of $file";
        if ( !-e $file ) {
            if ( $opt{missingFileDummy} ) {
                say "WARNING:  $file not found";
                my $tmpfile = "$globaltmpdir/" . basename($file) . "_" . $count++;
                open( my $TMP, '>', $tmpfile ) or die "ERROR: Cannot open file for writing:  $tmpfile\n\n";
                print $TMP "FILE NOT FOUND: $file";
                close $TMP;
                $file = $tmpfile;
            } else {
                say "WARNING:  $file not found.  Exiting";
                exit 1;
            }
        }
        if ( -f $file or -l $file ) {
            if ( $opt{verbose} ) {
                say "Original file:";
                chomp( my $lsl = `ls -l '$file'` );
                my $lines = getNumLines("cat $file");
                my $words = getNumLines( "cat $file", '-w' );
                say "$lsl    $lines lines    $words words";
            }
        }
        $count++;
    }
}
# TODO need to sanity check files vs dirs
#if ( ... ) {
#    say "\@dirs '@dirs'    \@files '@files'";
#    die "ERROR:  Cannot mix files and directories\n";
#}
if ( $opt{tree} ) {
    # Comparing two directories instead of two files
    my @dirs = @files;
    @files = ();
    my $count = 1;
    for my $dir (@dirs) {
        my $tmpfile = "$globaltmpdir/" . basename($dir) . "_" . $count++;
        open( my $TMP, '>', $tmpfile ) or die "ERROR: Cannot open file for writing:  $tmpfile\n\n";
        my $lslr;
        my @lslr;
        my $text;
        if ( whichCommand('tree') ) {
            $text = `tree -s '$dir'`;
        } else {
            @lslr = `ls -lR '$dir'`;
            d '@lslr';
            for my $line (@lslr) {
                d '$line';
                my @fields = split /\s+/, $line;
                d '@fields';
                if ( $line =~ /^d/ ) {
                    $text .= $line;
                } else {
                    my ( $size, $filename ) = @fields[ 2, 5 ];
                    #$filename =~ s|^$basefile/||;
                    $text .= "$size  $filename\n";
                }
            }
        }
        print $TMP $text;
        push @files, $tmpfile;
        close $TMP;
    }
    # end @dirs (comparing directories)
} elsif ( $opt{tartv} ) {
    # Compare tarfiles using tar -tv, and look at the file size
    #     Would also be nice if it do something to each of those files, for example md5sum or -externalPreprocessScript <script>
    #
    # If this option is not used, it will simply gvimdiff the tarballs:
    #     dif //ate/foo_dir.tar.gz#2 #3 -comments
    my @origFiles = @files;
    @files = ();
    my $count = 1;
    for my $f (@origFiles) {
        my $basefile = basename($f);
        $basefile =~ s/\.tar(\.(gz|bz2|xz|Z|zip))?$//;
        d '$basefile';
        my $tmpfile = "$globaltmpdir/" . basename($f) . "_" . $count++;
        d '$tmpfile';
        open( my $TMP, '>', $tmpfile ) or die "ERROR: Cannot open file for writing:  $tmpfile\n\n";
        my $zipCat = extension2zipcat($f);
        d '$zipCat';
        die "ERROR:  File $f is tar a tar file" if basename($f) !~ /\.tar/;
        my @tar = `$zipCat '$f' | tar -tv`;
        d '@tar';
        my $text;

        for my $line ( sort @tar ) {
            my @fields = split /\s+/, $line;
            my ( $size, $filename );
            if ( scalar @fields == 9 ) {
                # -r--r--r-- ckoknat hardware 187 Sep 19 2015 12:18 case10a_tar/case01a_hosts.txt  (macOS)
                ( $size, $filename ) = @fields[ 3, 8 ];
            } elsif ( scalar @fields == 6 ) {
                # -r--r--r-- ckoknat/hardware 187 2015-09-17 12:18 case10a_tar/case01a_hosts.txt   (Linux)
                ( $size, $filename ) = @fields[ 2, 5 ];
            } else {
                die "ERROR:  Could not parse output of  tar -tv\n        $line";
            }
            $filename =~ s|^$basefile/||;
            $text .= "$size  $filename\n";
        }
        d '$text';
        print $TMP $text;
        push @files, $tmpfile;
        close $TMP;
    }
}

my @fieldColumnWidths;
if ( $opt{fieldJustify} ) {
    @fieldColumnWidths = getFieldColumnWidths(@files);
}

# Handle -report with preprocessing
# Algorithm:
#     Create data structure listing pairs of files
#         2nd file is from from 2nd directory, or options -dir2 or -gold
if ( $opt{report} ) {
    my $reportFilePairs;
    if ( $opt{filePairs} or $opt{filePairsWithOptions} ) {
        # Only display the filenames which exist and mismatch, possibly with the dif command and options
        $reportFilePairs = 1;
    } else {
        $reportFilePairs = 0;
    }
    my $commandLineWithoutFilesModified = $commandLineWithoutFiles;
    for my $opt (qw( ppOnly silent quiet verbose gui difftool diff gvimdiff tkdiff kdiff3 kompare meld keeptmp gold dir2 report filePairs filePairsWithOptions includeFiles excludeFiles recursive noDirs noBackGroundProcess installationInstructions)) {
        $commandLineWithoutFilesModified =~ s/\s+-$opt\b//;
    }
    d '$commandLineWithoutFilesModified';
    my @filePairs;
    my $maxLength = 0;
    if ( !$opt{gold} and !$opt{dir2} and !defined $opt{includeFiles} ) {
        d "Option -report must be used with either -dir2 or -gold or -includeFiles <regex>\n";
        #die "ERROR:  option -report must be used with either -dir2 or -gold or -includeFiles <regex>\n";
    }
    # Construct @filePairs
    d '@files';
    my $printToScreen;
    if ( $opt{dir2} ) {
        die "ERROR:  Directory $opt{dir2} not found!\n" if !-d $opt{dir2};
        for my $file (@files) {
            next if -d $file;
            my $dir2file = toDir2($file);
            push @filePairs, $file;
            push @filePairs, $dir2file;
            $maxLength = length($file) if length($file) > $maxLength;
        }
        $printToScreen = 0;
    } elsif ( $opt{gold} ) {
        # For regression testing
        #     ~/r/k/dif -gold file1 file3 file4 file5
        for my $file (@files) {
            next if -d $file;
            my ( $goldfile, $position ) = toFromGolden($file);
            if ( $position == 1 ) {
                push @filePairs, $goldfile;
                push @filePairs, $file;
            } else {
                push @filePairs, $file;
                push @filePairs, $goldfile;
            }
            $maxLength = length($file) if length($file) > $maxLength;
        }
        $printToScreen = 0;
    } elsif ( defined $files[1] and defined $opt{includeFiles} ) {
        # Create @filePairs
        $files[0] = readlink( $files[0] ) if -l $files[0];
        $files[1] = readlink( $files[1] ) if -l $files[1];
        @filePairs = findFilePairs( $files[0], $files[1], $opt{includeFiles}, $opt{excludeFiles} );
        d '@filePairs';
        $printToScreen = 0;
    } else {
        # Print file sizes and md5sums to screen
        # dif dir/* -report
        # dif */file -report
        if ( -d $files[0] ) {
            my $dir = shift;
            my @fileList;
            File::Find::find( sub { -f and push @fileList, $File::Find::name }, $dir );
            d '@fileList';
            @files = @fileList;
        }
        for my $file (@files) {
            # Future improvement:  this does twice the necessary work, since we're not comparing two different sets of files
            push @filePairs, $file;
            push @filePairs, $file;
            $maxLength = length($file) if length($file) > $maxLength;
        }
        $printToScreen = 1;
    }
    d '@filePairs';
    my $numFilePairs = scalar(@filePairs) / 2;
    my $count        = 0;
    my $pairCount    = 0;
    my ( $dir1, $dir2 );
    if ( -d $files[0] and -d $files[1] ) {
        # dif dir1 dir2 -report
        $dir1 = $files[0];
        $dir2 = $files[1];
    } elsif ( $opt{dir2} ) {
        # dif files* -dir2 path -report
        $dir1 = dirname( $files[0] );    # This is the correct solution for  dif.pl /home/ate/scripts/release/gp100trial/a01/CAD/* -dir2 /home/ate/scripts/CAD -report
        $dir2 = $opt{dir2};
    } elsif ( $opt{gold} ) {
        # dif files* -gold -report
        $dir1 = 'GOLDEN';
        $dir2 = 'NEW';
    } else {
        # dif dir1 -report
        $dir1 = $files[0];
        $dir2 = defined $files[1] ? $files[1] : "$files[0]_";
    }
    #my $tmpfileReport1 = sprintf( "%s__%s", basename($0), $dir1);
    my $tmpfileReport1 = "_$dir1";       # _ is needed in case the dir is '.'
    $tmpfileReport1 =~ s{/}{_}g;
    $tmpfileReport1 = "$globaltmpdir/" . $tmpfileReport1;
    open( my $REPORT1, ">", $tmpfileReport1 ) or die "ERROR: Cannot open file for writing:  $tmpfileReport1\n\n";
    #my $tmpfileReport2 = sprintf( "%s__%s", basename($0), $dir2);
    my $tmpfileReport2 = "_$dir2";
    $tmpfileReport2 =~ s{/}{_}g;
    $tmpfileReport2 = "$globaltmpdir/" . $tmpfileReport2;
    open( my $REPORT2, ">", $tmpfileReport2 ) or die "ERROR: Cannot open file for writing:  $tmpfileReport2\n\n";
    d '$dir1 dir2 $tmpfileReport1 $tmpfileReport2';
    unless ( $opt{quiet} ) {
        say "Generating reports with file sizes, number of lines, and hashes at $tmpfileReport1 and $tmpfileReport2";
        say "    The two temporary report files will be automatically removed afterwards, unless -keeptmp is used" unless $opt{keeptmp};
    }
    my $hashLength;
    if ($atHome) {
        $hashLength = 16;
    } else {
        $hashLength = 32;
    }
    my $underscores = '_' x ( ( $hashLength - 16 ) / 2 );
    my $format;
    if ($reportFilePairs) {
        # -filePairs
        #     dirA/file1 dirB/file1
        #     dirA/file3 dirB/file3
        # -filePairsWithOptions
        #     dif dirA/file1 dirB/file1 -white
        #     dif dirA/file3 dirB/file3 -white
        $format = "%s\n";
    } elsif ( $opt{fast} ) {
        $format = "%10s  %s\n";
        printf $REPORT1 $format, 'BYTES', 'FILENAME';
        printf $REPORT2 $format, 'BYTES', 'FILENAME';
    } else {
        $format = "%10s  %8s  %${hashLength}s  %s\n";
        printf $REPORT1 $format, 'BYTES', 'LINES', 'HASH', 'FILENAME';
        printf $REPORT2 $format, 'BYTES', 'LINES', 'HASH', 'FILENAME';
    }

    my @mismatches;
    while (@filePairs) {
        my ( $file1, $file2, $tmpfile1, $tmpfile2, $size1, $size2, $numlines1, $numlines2, $hash1, $hash2, $fastOK );
        $file1 = shift(@filePairs);
        $file2 = shift(@filePairs);
        d '$file1 $file2';
        $count++;
        $pairCount++;
        if ( -f $file1 ) {
            if ( -r $file1 ) {
                if ( $opt{fast} ) {
                    if ($preprocessOptions) {
                        die "ERROR:  -report -fast may not be used in conjunction with any of the preprocessing options\n";
                    }
                    $size1     = sprintf( "%10s", -s $file1 );
                    $numlines1 = "";
                    $hash1     = '_' x $hashLength;
                    $fastOK    = 1;
                }
                if ( !$fastOK ) {
                    $tmpfile1 = determineTmpFilename( $file1, $count );
                    if ($preprocessOptions) {
                        preprocessFile( $file1, $tmpfile1, "$pairCount/$numFilePairs", $count % 2 );    # %2 for -start2 -stop2
                    } else {
                        $tmpfile1 = $file1;
                    }
                    $size1     = sprintf( "%10s", -s $tmpfile1 );
                    $numlines1 = getNumLines("cat $tmpfile1");
                    $hash1     = getHash( file => $tmpfile1 );
                    if ( ( $hashLength - length($hash1) ) > 0 ) {
                        $hash1 = '_' x ( ( $hashLength - length($hash1) ) / 2 ) . $hash1 . '_' x ( ( $hashLength - length($hash1) ) / 2 );    # pad with _ for 32 total characters
                    }
                }
            } else {
                $size1     = "";
                $numlines1 = "";
                $hash1     = "${underscores}__NOT_READABLE__${underscores}";
            }
        } elsif ( -d $file1 ) {
            $size1     = getNumLines("find $file1 -type f | wc -l");                                                                          # TODO the 'wc -l' here should probably be omitted, since that is done in getNumLines()
            $numlines1 = "";
            $hash1     = "${underscores}___DIRECTORY____${underscores}";
        } else {
            $size1     = "";
            $numlines1 = "";
            $hash1     = "${underscores}_DOES_NOT_EXIST_${underscores}";
        }
        $count++;
        if ( -f $file2 ) {
            if ( -r $file2 ) {
                if ($fastOK) {
                    $size2     = sprintf( "%10s", -s $file2 );
                    $numlines2 = "";
                    $hash2     = '_' x $hashLength;
                } else {
                    $tmpfile2 = determineTmpFilename( $file2, $count );
                    if ($preprocessOptions) {
                        preprocessFile( $file2, $tmpfile2, "$pairCount/$numFilePairs", $count % 2 );    # %2 for -start2 -stop2
                    } else {
                        $tmpfile2 = $file2;
                    }
                    $size2     = sprintf( "%10s", -s $tmpfile2 );
                    $numlines2 = getNumLines("cat $tmpfile2");
                    $hash2     = getHash( file => $tmpfile2 );
                    if ( ( $hashLength - length($hash2) ) > 0 ) {
                        $hash2 = '_' x ( ( $hashLength - length($hash2) ) / 2 ) . $hash2 . '_' x ( ( $hashLength - length($hash2) ) / 2 );    # pad with _ for 32 total characters
                    }
                }
            } else {
                $size2     = "";
                $numlines2 = "";
                $hash2     = "${underscores}__NOT_READABLE__${underscores}";
            }
        } elsif ( -d $file2 ) {
            $size2     = getNumLines("find $file2 -type f | wc -l");
            $numlines2 = "";
            $hash2     = "${underscores}___DIRECTORY____${underscores}";
        } else {
            $size2     = "";
            $numlines2 = "";
            $hash2     = "${underscores}_DOES_NOT_EXIST_${underscores}";
        }
        d '$size1 $size2 $numlines1 $numlines2 $hash1 $hash2';
        my ( $file1mod, $file2mod );
        if ( -d $files[0] and -d $files[1] ) {
            # dif dirA dirB
            ( $file1mod = $file1 ) =~ s{^$dir1/}{};
            ( $file2mod = $file2 ) =~ s{^$dir2/}{};
        } elsif ( $opt{dir2} ) {
            ( $file1mod = $file1 ) =~ s{^$dir1/}{};
            ( $file2mod = $file2 ) =~ s{^$dir2/}{};
        } elsif ( $opt{gold} ) {
            ( $file1mod, my $position ) = toFromGolden($file1);
            ( $file2mod = $file2 );
        } else {
            # */file -report
            ( $file1mod = $file1 );
            ( $file2mod = $file2 );
        }
        $file1mod =~ s{^\./}{};
        $file2mod =~ s{^\./}{};
        if ( $opt{fast} ) {
            if ($reportFilePairs) {
                # -filePairs or -filePairsWithOptions
                if ( $size1 ne '' and $size2 ne '' and $size1 ne $size2 ) {
                    if ( $opt{filePairs} ) {
                        printf $REPORT1 $format, "$file1\t$file2";
                    } else {
                        # -filePairsWithOptions
                        printf $REPORT1 $format, "$commandLineWithoutFilesModified $file1 $file2";
                    }
                    push @mismatches, $file1mod;
                }
            } elsif ( $opt{intersection} and ( $size1 eq '' or $size2 eq '' ) ) {
                # do nothing
            } else {
                printf $REPORT1 $format, $size1, $file1mod;
                printf $REPORT2 $format, $size2, $file2mod;
                push @mismatches, $file1mod if $size1 ne $size2;
            }
        } else {
            if ($reportFilePairs) {
                # -filePairs or -filePairsWithOptions
                if ( $hash1 !~ /DOES_NOT_EXIST/ and $hash2 !~ /DOES_NOT_EXIST/ and $hash1 ne $hash2 ) {
                    if ( $opt{filePairs} ) {
                        printf $REPORT1 $format, "$file1\t$file2";
                    } else {
                        # -filePairsWithOptions
                        printf $REPORT1 $format, "$commandLineWithoutFilesModified $file1 $file2";
                    }
                    push @mismatches, $file1mod;
                }
            } elsif ( $opt{intersection} and ( $size1 eq '' or $size2 eq '' ) ) {
                # do nothing
            } else {
                printf $REPORT1 $format, $size1, $numlines1, $hash1, $file1mod;
                printf $REPORT2 $format, $size2, $numlines2, $hash2, $file2mod;
                push @mismatches, $file1mod if $hash1 ne $hash2;
            }
        }
    }
    close $REPORT1;
    close $REPORT2;
    if ($printToScreen) {
        ls "$tmpfileReport1";
        say "\n" . `cat $tmpfileReport1`;
        exit 0;
    }
    @files = ( $tmpfileReport1, $tmpfileReport2 );
    if ( $opt{fast} ) {
        say "File comparison was done using only file sizes (not checksums) because of option -fast" unless $opt{quiet};
    } else {
        if ( !$preprocessOptions ) {
            say "File comparison was done using checksums.  To compare using only file sizes, use option -fast" unless $opt{quiet};
        }
    }
    d '@mismatches';
    # The exit statuses below are used in regressions
    if (@mismatches) {
        say "Found " . scalar(@mismatches) . " mismatching pairs of files" unless $opt{quiet};
    } else {
        if ( $opt{fast} ) {
            say "All file pairs have matching file sizes (contents not checked because of option -fast)" unless $opt{quiet};
        } else {
            say "All file pairs match" unless $opt{quiet};
        }
        exit 0;
    }
}

# If all files match md5sum, there is no need to uncompress or preprocess
if ( scalar @files == 2 and !$opt{report} and !defined $opt{start2} and !defined $opt{stop2} and $files[0] !~ m{^//} and $files[1] !~ m{^//} and $files[0] !~ /#(\d+|head)$/ and $files[1] !~ /#(\d+|head)$/ and $files[0] !~ m{^\S+:/} and $files[1] !~ m{^\S+:/} ) {
    my @mismatch = filesMismatch(@files);
    d '@mismatch';
    if ( !@mismatch ) {
        say "These files are identical.  Exiting.\n" unless $opt{quiet};
        exit 0;
    }
}

# Preprocess files
my $count          = 0;
my @localFiles     = ();    # original files or files immediately after p4 print
my @processedFiles = ();    # files after all processing, gunzipping, etc
for my $f (@files) {
    #LS($f);
    $count++;
    if ( $opt{report} ) {
        # Don't process the report, as that would lead to filenames being processed, for example with -search -replace
        push @processedFiles, $f;
        push @localFiles,     $f;
    } else {
        if ($preprocessRequired) {
            my $tmpfile = determineTmpFilename( $f, $count );
            push @processedFiles, preprocessFile( $f, $tmpfile, $count, $count );
        } else {
            d 'No options used, so no need to preprocess';
            push @processedFiles, $f;
            push @localFiles,     $f;
            #system("ln -s $f $tmpfile");
        }
    }
}
d '@processedFiles $preprocessRequired';

# Check if all processed files are zero size
my $allProcessedFilesZeroSize = 1;
if ($preprocessRequired) {
    say "Processed files:" if $opt{verbose} and !$opt{report};
    for my $file (@processedFiles) {
        if ( $opt{verbose} and !$opt{report} ) {
            chomp( my $lsl = `ls -l '$file'` );
            my $lines = getNumLines("cat $file");
            my $words = getNumLines( "cat $file", '-w' );
            say "$lsl    $lines lines    $words words";
        }
        if ( -s $file ) {
            #d("File $file has zero size");
            $allProcessedFilesZeroSize = 0;
        }
    }
    if ($allProcessedFilesZeroSize) {
        say "WARNING:  All processed files are zero size!" unless $opt{quiet};
        exit 0;
    }
}

# Exit early (after preprocess) for -ppOnly
if ( $opt{ppOnly} ) {
    say "Exiting because of option -ppOnly\n" unless $opt{quiet};
    exit 0;
}

# Exit early (after preprocess)
if ( !defined $files[1] and not $opt{stdout} and not defined $opt{out} ) {
    say "Exiting because only one file was specified\n";
    exit 0;
}

# @localFiles are original files or files immediately after p4 print
# @processedFiles are files after all processing, gunzipping, etc
# Check if files/directories are identical
# Uncompress files if needed beforehand
my $processedFiles = join " ", @processedFiles;
d '$processedFiles';
say "Comparing with $zipDiff..." if scalar(@files) == 2 and not -d $files[0] and not $opt{quiet};
if ( scalar(@files) == 2 and not -d $files[0] and not $opt{stdout} and not defined $opt{out} and !$opt{bin} ) {
    d 'doing a diff';
    system("$zipDiff $processedFiles > /dev/null");
    d "Status = $?";
    exit $? >> 8 if $opt{quiet} or $gui eq 'none';
    # Check exit status
    if ( $? == 0 ) {
        # Files match, no need to run gui
        d '@files @localFiles @processedFiles';
        my @status = filesMismatch(@localFiles);
        if (@status) {
            # Files mismatched before preprocessing, matched afterwards
            if ($allProcessedFilesZeroSize) {
                # This is redundant, but leaving it here for clarity
                say "WARNING:  These files are both zero size after preprocessing.  Exiting.\n" unless $opt{quiet};
            } else {
                say "These files are identical after preprocessing.  Exiting.\n" unless $opt{quiet};
            }
            say "md5sum  $status[0]  $localFiles[0]"   if $opt{verbose};
            say "md5sum  $status[1]  $localFiles[1]\n" if $opt{verbose};
        } else {
            # Files matched, even before preprocessing
            say "These files are identical.  Exiting.\n" unless $opt{quiet};
        }
        exit 0;
    }
}
ls $processedFiles;

# Use gvimdiff instead of meld or kompare once the file size reaches a limit
if ( $gui =~ /meld|kompare/ ) {
    #     10MB uncompressed file takes 2 seconds on gvimdiff vs 39 seconds on kompare and similar on meld (meld will open but not show differences for a while)
    if ( $processedFiles[0] =~ /\.(gz|zip|bz2|xz|Z|zip)$/ ) {
        # This only happens if the processed file is compressed, meaning that we haven't done processing on it
        # This is not the case for meld, as we have already done  gunzip -c $file > $processedFile
        $defaults{meldSizeLimit} /= 10;
    }
    chomp( my $uid = `whoami` );
    if ( $atHome and $gui eq 'meld' ) {
        # work environment
        my $guiWithLineNumbers;
        if ( $uid eq 'ckoknat' ) {
            $guiWithLineNumbers = 'kompare';
        } else {
            $guiWithLineNumbers = 'gvimdiff';
        }
        my $executable_regex = '.(c|cpp|h|java|js|pl|pm|py|tn|tcl)($|#)';
        if ( basename( $processedFiles[0] ) =~ /$executable_regex/ ) {
            # Switch to kompare, since line numbers are needed when viewing source code, and my meld environment does not support them
            say "Switching to $guiWithLineNumbers to support line numbers because files are source code" unless $opt{quiet};
            $gui = $guiWithLineNumbers;
        }
        if ( 0 and defined $files[2] or defined $files[1] and $opt{gold} ) {
            # My meld environment seems to have issues with opening many files
            $gui = 'kompare';
        }
    } else {
        my $sizeProcessedFile0 = -s $processedFiles[0];
        if ( $sizeProcessedFile0 > $defaults{meldSizeLimit} ) {
            # Using -e because do not want to run these checks if run with p4 revs:  dif releasePatternsRev.pl#136 #140
            say "Switching to gvimdiff to speed up comparison because size of 1st file ($sizeProcessedFile0) is > $defaults{meldSizeLimit} bytes" unless $opt{quiet};
            say "If you really want to stay with $gui, change the meldSizeLimit in ~/.$scriptName.defaults"                                       unless $opt{quiet};
            $gui = 'gvimdiff';
        }
    }
    d '$gui';
}
( my $guiAbbrev = $gui ) =~ s/^(\S+).*/$1/;
if ( $guiAbbrev =~ /^(gvimdiff)$/ and !$opt{keeptmp} ) {
    # In contrast to meld, gvimdiff by default forks a subprocess
    # Wait for gvimdiff to finish before cleaning up files
    $gui .= ' --nofork';
}
say "Opening $guiAbbrev GUI..." if scalar(@files) == 2 and not $opt{quiet};

# Run meld/gvimdiff/kdiff3/tkdiff/kompare
my $command;
if ( defined $opt{out} ) {
    my $dir = dirname( $opt{out} );
    `mkdir -p $dir` if !-d $dir;
    die "ERROR: Could not create directory $dir\n\n" if !-d $dir;
    if ( $opt{stdout} ) {
        $command = $windows ? "type $processedFiles" : "cat $processedFiles | tee $opt{out}";
    } else {
        $command = $windows ? "type $processedFiles" : "cat $processedFiles > $opt{out}";
    }
} elsif ( $opt{stdout} ) {
    #$command = $windows ? "type $processedFiles" : "cat $processedFiles";
    if ( $opt{verbose} ) {
        for my $file (@processedFiles) {
            $command .= "echo '\n### $file ###' ; ";
            $command .= "cat '$file' ; ";
        }
    } else {
        $command = "cat $processedFiles";
    }
} elsif ( $opt{noBackgroundProcess} ) {
    # Added automatically for dif //path/file#1..#3  and  for -dir2 when multiple files are chosen
    $command = "$gui $processedFiles";
} elsif ( $gui eq 'vim -d' ) {
    # Prevent files from being cleaned up
    $command = "$gui $processedFiles ; sleep 2";
} else {
    my $tee;
    # from
    # diff fileA fileB
    # to
    # diff fileA fileB | tee $opt{tee}
    if ( $opt{tee} ) {
        $tee = " | tee $opt{tee}";
    } else {
        $tee = "";
    }
    if ( $opt{keeptmp} ) {
        $command = "$gui $processedFiles $tee &";
    } else {
        # No '&', will wait for user to close the GUI so that temp dir can be deleted
        $command = "$gui $processedFiles $tee";
    }
}
d '$command';
say "Executing  $command" if $opt{verbose};
if ( $d and not $opt{stdout} ) {
    say "Exiting because d = $d\n";
    exit 0;
}
if ( !$opt{stdout} and scalar(@files) > 2 and $gui =~ /(kompare|tkdiff)$/ ) {
    say "Not running $gui because it only takes 2 files";
    exit 1;
}
if ( $files[0] =~ /\.p[lm]$/ and not $opt{perltidy} ) {
    say "You seem to be comparing Perl source files.  You may want to use the -perltidy option next time." unless $opt{quiet};
}
if ( getFileType( $files[0] ) =~ /^(yml|yaml)$/ and not $opt{yaml} ) {
    say "You seem to be comparing YAML files.  You may want to use the -yaml option next time to improve the formatting." unless $opt{quiet};
}
if ( getFileType( $files[0] ) eq 'json' and not $opt{json} ) {
    say "You seem to be comparing JSON files.  You may want to use the -json option next time to improve the formatting." unless $opt{quiet};
}
if ( getFileType( $files[0] ) eq 'binl' and not $opt{strings} ) {
    say "You seem to be comparing binl files.  You may want to use the -strings option next time to remove the binary characters." unless $opt{quiet};
}
d '$command';
d "after getFileType (2)";
say "" unless $opt{stdout};
system($command);    # system() runs an command and waits for it to return
#say "Exiting";
exit 0;

### END MAIN ###

# my $tmpfile = preprocessFile( $file, $tmpfile, $filenum, $filenumStartStop )
sub preprocessFile {
    my ( $file, $tmpfile, $filenum, $filenumStartStop ) = @_;
    d '$file $tmpfile $filenum %scms';
    d '.';
    $filenumStartStop = 2 if $filenumStartStop > 2;    # Normally there are 2 files, but with 3-file comparison, the 3rd file will use the -start2 -stop2 parameters
    if ( $scms{Perforce} or $scms{SVN} or $scms{GIT} ) {
        # May need to  p4 print file  or  svn cat file  or  git show file
        $file = handleSCM($file);
    } else {
        # do nothing
    }
    if ( $file =~ m{^\S+:/} ) {
        # host:/path/file
        $file = handleScp($file);
    }
    push @localFiles, $file;

    my ( @startRegexesAll, @startRegexes, $start, $stop );
    if ( $opt{"start$filenumStartStop"} ) {
        $start = $opt{"start$filenumStartStop"};
        @startRegexes = split /\^\^/, $opt{"start$filenumStartStop"};
    } else {
        $start = $opt{start};
        @startRegexes = split /\^\^/, $opt{start} if defined $opt{start};
    }
    @startRegexesAll = @startRegexes;
    d '@startRegexes';
    $start = shift(@startRegexes);
    #$start = $startRegexes[0];
    if ( $opt{"stop$filenumStartStop"} ) {
        $stop = $opt{"stop$filenumStartStop"};
    } else {
        $stop = $opt{stop};
    }
    d '@startRegexes $start $stop \n$file $tmpfile $count';

    # Handle preprocessing from external preprocessing script or bcpp or perltidy
    my $zipCat = extension2zipcat($file);
    d '$zipCat';
    #say "Decompressing $file" if $zipCat ne 'cat' and not $opt{quiet};
    my $F;
    if ( $opt{perlEval} or $opt{yaml} or $opt{json} or $opt{functionSort} ) {
        my $result;
        if ( $opt{perlEval} ) {
            $result = sortYamlPerlJson( $file, $zipCat, 'perlEval' );
        } elsif ( $opt{yaml} ) {
            $result = sortYamlPerlJson( $file, $zipCat, 'yaml' );
        } elsif ( $opt{json} ) {
            $result = sortYamlPerlJson( $file, $zipCat, 'json' );
        } elsif ( $opt{functionSort} ) {
            $result = functionSort($file);
        } else {
            die "Program bug";
        }
        my $tmpfilePerlEvalEtc = sprintf( "$globaltmpdir/%s_%s_%s.yamljson", basename($0), $$, basename($file) );
        open( my $TMP2, ">", $tmpfilePerlEvalEtc ) or die "ERROR: Cannot open file for writing:  $tmpfilePerlEvalEtc\n\n";
        print $TMP2 $result;
        close $TMP2;
        open( $F, "cat '$tmpfilePerlEvalEtc' |" ) or die "ERROR: Cannot open file for reading:  $tmpfilePerlEvalEtc\n\n";
    } elsif ( $file =~ /\.pdf$/ ) {
        my $tmpfile;
        eval 'use CAM::PDF ()';
        if ($@) {
            say "ERROR:  Install CAM::PDF from CPAN to parse pdf files";
            say "        sudo cpan install CAM::PDF";
            exit 1;
        } else {
            $tmpfile = sprintf( "$globaltmpdir/%s_%s_%s.dumpPDF", basename($0), $$, basename($file) );
            open( my $TMP, ">", $tmpfile ) or die "ERROR: Cannot open file for writing:  $tmpfile\n\n";
            my $pagelist = undef;
            no warnings;
            my $doc = CAM::PDF->new($file) || die "$CAM::PDF::errstr\n";
            use warnings;
            for my $p ( $doc->rangeToArray( 1, $doc->numPages(), $pagelist ) ) {
                my $str = $doc->getPageText($p);
                if ( defined $str ) {
                    CAM::PDF->asciify( \$str );
                    print $TMP $str;
                }
            }
            close $TMP;
            ls $tmpfile;
        }
        open( $F, "cat '$tmpfile' |" ) or die "ERROR: Cannot open file for reading:  $tmpfile\n\n";
    } elsif ( $file =~ /\.(ods)$/ ) {
        eval 'use Spreadsheet::Read ();  use Spreadsheet::ParseODS ()';
        if ($@) {
            say "\n$@\n";
            say "ERROR:  Install Spreadsheet::Read and Spreadsheet::ParseODS from CPAN to parse .ods spreadsheets";
            say "        sudo cpan install Spreadsheet::Read Spreadsheet::ParseODS";
            exit 1;
        } else {
            my $tmpfile = sprintf( "$globaltmpdir/%s_%s_%s.dumpODS", basename($0), $$, basename($file) );
            open( my $TMP, ">", $tmpfile ) or die "ERROR: Cannot open file for writing:  $tmpfile\n\n";
            # DEBUG sub preprocessFile:  $book = [
            #     {
            #       'error' => undef,
            #       'parser' => 'Spreadsheet::ParseXLSX',
            #       'parsers' => [
            #                      {
            #                        'parser' => 'Spreadsheet::ParseXLSX',
            #                        'type' => 'xlsx',
            #                        'version' => '0.27'
            #                      }
            #                    ],
            #       'sheet' => {
            #                    'my_second_sheet' => 2,
            #                    'my_first_sheet' => 1,
            #                  },
            #       'sheets' => 2,
            #       'type' => 'xlsx',
            #       'version' => '0.27'
            #     },
            #     {
            #       'A1' => 'Name',  # sheet 1
            #       'A2' => 'foo',
            #       'A3' => 'bar',
            #     },
            #     {
            #       'A1' => 'Name',  # sheet 2
            #       'A2' => 'baz',
            #       'A3' => 'qux',
            #     }
            #   }
            # ]
            #d '$book';
            my $book = Spreadsheet::Read::ReadData($file) || die "Could not open '$file': $!";
            my @sheetMapping;
            for my $sheetName ( keys %{ $book->[0]{sheet} } ) {
                $sheetMapping[ $book->[0]{sheet}{$sheetName} ] = $sheetName;
            }
            #d '@sheetMapping';
            for my $sheetNum ( 1 .. @sheetMapping - 1 ) {
                #d '$sheetNum';
                print $TMP '*** ', $sheetMapping[$sheetNum], " ***\n";
                #print '*** ', $sheetMapping[$sheetNum], " ***\n";
                my @rows = Spreadsheet::Read::rows( $book->[$sheetNum] );
                #d '@rows';
                for my $row (@rows) {
                    no warnings qw(uninitialized);
                    print $TMP join( '|', @$row ), "\n";
                    #print join( '|', @$row ), "\n";
                }
            }
            close $TMP;
            ls $tmpfile;
            open( $F, "cat '$tmpfile' |" ) or die "ERROR: Cannot open file for reading:  $tmpfile\n\n";
        }
    } elsif ( $file =~ /\.(xls[mx]?)$/ ) {
        eval 'use Spreadsheet::BasicRead ()';
        if ($@) {
            say "\n$@\n";
            say "ERROR:  Install modules from CPAN to parse xls|xlsm|xlsx spreadsheets";
            say "        sudo cpan";
            say "            install Spreadsheet::BasicRead";
            say "            install Spreadsheet::ParseExcel    (for xls)";
            say "            install Spreadsheet::XLSX          (for xlsx)";
            exit 1;
        } else {
            if ( $file =~ /\.(xls)$/ ) {
                eval 'use Spreadsheet::ParseExcel ()';
                if ($@) {
                    say "\n$@\n";
                    say "ERROR:  Install ParseExcel from CPAN to parse xls spreadsheets";
                    say "        sudo cpan";
                    say "            install Spreadsheet::ParseExcel";
                    exit 1;
                }
                d '. using Spreadsheet::ParseExcel';
            } elsif ( $file =~ /\.(xls[mx])$/ ) {
                eval 'use Spreadsheet::XLSX ()';
                if ($@) {
                    say "\n$@\n";
                    say "ERROR:  Install Spreadsheet::XLSX from CPAN to parse xlsx spreadsheets";
                    say "        sudo cpan";
                    say "            install Spreadsheet::XLSX";
                    exit 1;
                }
                d '. using Spreadsheet::XLSX';
            } else {
                die "Program bug!";
            }
            my $tmpfile = sprintf( "$globaltmpdir/%s_%s_%s.dumpXLS", basename($0), $$, basename($file) );
            open( my $TMP, ">", $tmpfile ) or die "ERROR: Cannot open file for writing:  $tmpfile\n\n";
            my $ss = new Spreadsheet::BasicRead($file) || die "Could not open '$file': $!";
            while (1) {
                my $sheetName = $ss->currentSheetName();
                my $printSheet;
                if ( defined $opt{xlsSheetName} ) {
                    if ( $sheetName =~ /$opt{xlsSheetName}/ ) {
                        $printSheet = 1;
                    } else {
                        $printSheet = 0;
                    }
                } else {
                    $printSheet = 1;
                }
                d '$sheetName $printSheet';
                if ($printSheet) {
                    print $TMP "*** $sheetName ***\n";
                    # Print the data for each row of the spreadsheet to stdout using '|' as a separator
                    my $row = 0;
                    while ( my $data = $ss->getNextRow() ) {
                        no warnings qw(uninitialized);
                        $row++;
                        #print $TMP join('|', $row, @$data), "\n";
                        print $TMP join( '|', @$data ), "\n";
                    }
                }
                last if !$ss->getNextSheet();
            }
            close $TMP;
            ls $tmpfile;
            open( $F, "cat '$tmpfile' |" ) or die "ERROR: Cannot open file for reading:  $tmpfile\n\n";
        }
    } else {
        my $preprocess_pipe = "";    #  Later on, this will happen "$zipCat '$file' $preprocess_pipe |"
        if ( $opt{bin} ) {
            if ( $opt{externalPreprocessScript} ne '' ) {
                die "ERROR:  Cannot run -externalPreprocessScript in combination with -bin\n";
            } elsif ( $opt{externalPreprocessScript2} ne '' ) {
                die "ERROR:  Cannot run -externalPreprocessScript2 in combination with -bin\n";
            } elsif ( $opt{externalPreprocessScript3} ne '' ) {
                die "ERROR:  Cannot run -externalPreprocessScript3 in combination with -bin\n";
            } elsif ( -f '/usr/bin/xxd' ) {
                $opt{externalPreprocessScript} = '/usr/bin/xxd';
            } elsif ( -f '/usr/bin/hexdump' ) {
                $opt{externalPreprocessScript} = '/usr/bin/hexdump -c';
            } else {
                die "ERROR:  -bin option requires either /usr/bin/xxd or /usr/bin/hexdump\n";
            }
            $opt{bin} = undef;
        }
        if ( 0 and $tarPP ) {
            # TODO:
            #     Goal is simply to print tar header at top
            #     $tarPP is either 'tar -tv' or 'tar -tvz'
            #     Want to first print 'tar -tv' and then run 'strings' (which is already turned on)
            #     Mock this up first on a command line after 'cat'
            #     Later on, this will happen "$zipCat '$file' $preprocess_pipe |"
            my $tmpfile1 = determineTmpFilename( $file, $count + 1000000 );
            my $tmpfile2 = determineTmpFilename( $file, $count + 1000001 );
            my $tmpfile3 = determineTmpFilename( $file, $count + 1000002 );
            d '$tmpfile1 $tmpfile2 $tmpfile3';
            my $cmd = "$zipCat '$file' | tar -tv > $tmpfile1";
            #my $cmd = "$tarPP '$file' > $tmpfile1";
            d '$cmd';
            my $result = `$cmd`;
            d '$result';
            $cmd = "echo XXXXXXXXXXXXXXXX > $tmpfile2";
            d '$cmd';
            $result = `$cmd`;
            d '$result';
            $cmd = "$zipCat $file > $tmpfile3";
            d '$cmd';
            $result = `$cmd`;
            d '$result';
            $file =~ s/\.gz$//;    ### TODO need to improve this to handle other formats
            d '$file';
            $cmd = "cat $tmpfile1 $tmpfile2 $tmpfile3 > $file";
            d '$cmd';
            $result = `$cmd`;
            d '$result';
            #die;
        }
        if ( $opt{strings} ) {
            # This is a preprocess step so that any remaining junk could be preprocessed, for example with -search -replace
            $preprocess_pipe .= "| $opt{strings}";
        }
        if ( $opt{comments} ) {
            # multiline C comments
            # This is a preprocess step so that blank lines are removed during the main loop
            $preprocess_pipe .= "| perl -0777 -pe 's{/\\*.*?\\*/}{}gs'";
        }
        if ( $opt{externalPreprocessScript} ) {
            die "ERROR:  preprocessing script not found:  '$opt{externalPreprocessScript}'\n" if !whichCommand( $opt{externalPreprocessScript} );
            $preprocess_pipe .= "| $opt{externalPreprocessScript}";
        } elsif ( $opt{externalPreprocessScript2} or $opt{externalPreprocessScript3} ) {
            my $tmpfile1 = determineTmpFilename( $file, $count + 1000000 );
            my $tmpfile2 = determineTmpFilename( $file, $count + 1000001 );
            my ( $cmd, $result );
            $cmd = "$zipCat '$file' > $tmpfile1";
            d '$cmd';
            $result = `$cmd`;
            d '$result';
            if ( $opt{externalPreprocessScript2} ) {
                die "ERROR:  preprocessing script not found:  '$opt{externalPreprocessScript2}'\n" if !whichCommand( $opt{externalPreprocessScript2} );
                if ( $opt{externalPreprocessScript2} =~ m{^\S+/perl .*-e} ) {
                    # perl -I... -M... -e 'magic'    -->    perl -I... -M... -e 'magic' file1 file2
                    $cmd = "$opt{externalPreprocessScript2} $tmpfile1 $tmpfile2";
                } else {
                    # script.pl -options             -->    script.pl file1 file2 -options
                    $opt{externalPreprocessScript2} =~ /^(\S+)\s*(.*)$/;
                    my ( $extScript, $extOptions ) = ( $1, $2 );
                    $cmd = "$extScript $tmpfile1 $tmpfile2 $extOptions";
                }
            } else {
                die "ERROR:  preprocessing script not found:  '$opt{externalPreprocessScript3}'\n" if !whichCommand( $opt{externalPreprocessScript3} );
                # -externalPreprocessScript3
                # script.pl -options                 -->    script.pl -in file1 -out file2 -options
                $opt{externalPreprocessScript3} =~ /^(\S+)\s*(.*)$/;
                my ( $extScript, $extOptions ) = ( $1, $2 );
                $cmd = "$extScript -in $tmpfile1 -out $tmpfile2 $extOptions";
            }
            d '$cmd';
            $result = `$cmd`;
            d '$result';
            $preprocess_pipe .= "> /dev/null ; cat $tmpfile2";
        } elsif ( $opt{bcpp} ) {
            ( my $bcpp_executable = $defaults{bcpp} ) =~ s/^(\S+).*/$1/;
            if ( !-x $bcpp_executable ) {
                die "ERROR:  $bcpp_executable not found\n";
            }
            $preprocess_pipe .= "| $defaults{bcpp}";
        } elsif ( $opt{perltidy} ) {
            ( my $perltidy_executable = $defaults{perltidy} ) =~ s/^(\S+).*/$1/;
            if ( !-x $perltidy_executable ) {
                die "ERROR:  $perltidy_executable not found\n";
            }
            # perltidy -st sends output to stdout
            $preprocess_pipe .= "| $defaults{perltidy} -st";
        }
        d '$preprocess_pipe';
        my $openCommand = "$zipCat '$file' $preprocess_pipe |";
        d '$openCommand';
        open( $F, $openCommand ) or die "ERROR: Cannot open file for reading:  $file\n\n";
    }
    if ( $opt{verbose} ) {
        say "\n\n\n" if $opt{gold};    # To visually separate the diffs
        if ( $opt{report} or $opt{includeFiles} or $opt{dir2} or $opt{gold} ) {
            say "Preprocessing $filenum $file";
        } else {
            say "Preprocessing $filenum $file";
        }
    }
    d '$head $tail';
    my $numLines = "?";
    if ($tail) {
        $numLines = getNumLines("$zipCat '$file'");
        d '$numLines';
    }
    open( my $TMP, "$opt{sort} $opt{uniq} $opt{fold} $opt{dos2unix} > $tmpfile" ) or die "ERROR: Cannot open file for writing:  $tmpfile\n\n";    # Postprocess step
    my $firstLine;
    if ( $opt{tail} or $opt{tailLines} ) {
        # Later, it will use this logic:
        #     if ( $linenum < $firstLine ) {
        #         #d "Ignoring line because of option -tail";
        #         next;
        #     }
        #     if ( $linenum > $head ) {
        #         #d "Ignoring rest of file because of option -head";
        #         last;
        #     }
        if ( $opt{head} or $opt{headLines} ) {
            if ( $tail >= 0 ) {
                # keep only the middle
                # first keep $tail lines, then keep the first $head of those
                $firstLine = $head - $tail + 1;
            } else {
                # Alternate using negative numbers
                $firstLine = -$head + 1;
                $head      = $numLines + $tail;
            }
        } else {
            if ( $tail >= 0 ) {
                # keep the last $tail lines
                $firstLine = $numLines - $tail + 1;
            } else {
                # ignores the last $tail lines
                $firstLine = -1;
                $head      = $numLines + $tail;
            }
        }
    } else {
        if ( $head >= 0 ) {
            # keep the first $head lines
            $firstLine = -1;
        } else {
            # ignore the first $head lines
            $firstLine = -$head + 1;
            $head      = $MAXHEAD;
        }
    }
    d '$head $tail $numLines $firstLine';
    my $linenum       = 0;
    my $startFound    = 0;
    my $anyStartFound = 0;
    my $anyStopFound  = 0;
    my $stopFound     = 0;
    d '$start $stop';
    $startFound = 1 if defined $stop  and not defined $start;
    $stopFound  = 1 if defined $start and not defined $stop;
    d( '$startFound', 'nc*' );    # Turn on line numbers and chomp

    while ( my $line = <$F> ) {
        #d '.';  # comment this out for performance
        #d '$line';  # comment this out for performance
        $linenum++;

        # -case and -comments and -white are at top of loop, so that the change will affect -start -stop -grep etc
        if ( $opt{case} ) {
            $line = lc($line);
        }

        if ( $opt{comments} ) {
            # C-style comments are handled separately
            $line =~ s{\s*//.*}{};    # C++
            $line =~ s{\s*#.*}{};     # Perl
            $line =~ s{\s+$}{};       # After stripping comments, there are sometimes trailing spaces
            $line .= "\n" if $line =~ /\S/;
        }

        if ( $opt{white} ) {
            $line =~ s/^\s+//;
            $line =~ s/[ \t]+/ /g;
            $line =~ s/ $//g;
            $line =~ s/[^[:ascii:]]//g;    # remove any non-printable characters
        }
        if ( $opt{noWhite} ) {
            $line =~ s/^\s+//g;
            $line =~ s/[ \t]+//g;
            $line =~ s/^\n//g;
            $line =~ s/[^[:ascii:]]//g;    # remove any non-printable characters
        }
        if ( $opt{round} ) {
            # -round "%0.2f"
            $line =~ s/[-+]?\d*(?:\.?\d|\d\.)\d*(?:[eE][-+]?\d+)?/sprintf($opt{round},$&)/ge;
        }
        if ( $opt{basenames} ) {
            # path/file -> file
            $line =~ s{[\w\-\./]*/([\w\-\.]+)}{$1}g;
        }
        if ( $opt{extensions} ) {
            # path/file.extension -> .extension
            $line =~ s{([\w\-/]+)(\.[\w\-\.]+)}{$2}g;
        } elsif ( $opt{removeExtensions} ) {
            # path/file.extension -> path/file
            $line =~ s{([\w\-/]+)(\.[\w\-\.]+)}{$1}g;
        } else {
            # do nothing
        }
        if ( $opt{sortWords} ) {
            # sort words in current line
            chomp $line;
            $line = ( join ' ', sort( split /\s+/, $line ) ) . "\n";
        }

        if ( $linenum > $head ) {
            #d "Ignoring rest of file because of option -head";
            last;
        } elsif ( defined $stop and $startFound and !$stopFound and $line =~ /($stop)/ ) {
            my $match = $1;
            d "Stopping at line $linenum in file $filenum because -stop '$match' =~ /$stop/:  $line";
            $startFound   = 0;
            $stopFound    = 1;
            $anyStopFound = 1;
            if ( $opt{stopIgnoreLastLine} ) {
                #d "Because of -start and/or -stop, ignoring line $linenum:  $line";
                next;
            }
        } elsif ( defined $start and not $startFound and $line =~ /($start)/ ) {
            my $match = $1;
            d '.';
            d '$startFound $start @startRegexes';
            d "Found 'start' match at line $linenum in file $filenum $file because -start '$match' =~ /$start/:  $line";
            my $startNext = shift(@startRegexes);
            d '@startRegexes $startNext';
            if ( defined $startNext ) {
                $start = $startNext;
                d '$start';
            } else {
                d "All start conditions have been fulfilled for file $filenum";
                $startFound = 1;
                $stopFound  = 0;
                d '$startFound';
                $anyStartFound = 1;
                if ( $opt{startMultiple} ) {
                    # Set up for next start/stop
                    @startRegexes = @startRegexesAll;
                    $start        = shift(@startRegexes);
                } else {
                    $start = undef;
                }
                d '.';
            }
            if ( $opt{startIgnoreFirstLine} ) {
                #d "Because of -start and/or -stop, ignoring line $linenum:  $line";
                next;
            }
        } elsif ( ( defined $start or defined $stop ) and not $startFound ) {
            #d "Because of -start and/or -stop, ignoring line $linenum:  $line";
            next;
        } elsif ( ( $opt{function} ) and $line =~ /^\s*$/ ) {
            # Ignore blank lines
            next;
        } elsif ( $linenum < $firstLine ) {
            #d "Ignoring line because of option -tail";
            next;
        } elsif ( defined $opt{ignore} and $line =~ /$opt{ignore}/ ) {
            d "Ignoring line because of -ignore option ($opt{ignore}):  $line";
            next;
        } elsif ( defined $opt{grep} and $line !~ /$opt{grep}/ ) {
            #d "Bypassing line because it doesn't match -grep option ($opt{grep}):  $line";
            next;
        } else {
        }    # do nothing
             #d '$linenum $line';

        if ( $opt{search_replace} ) {
            #d '$opt{search_replace}';
            #d '\n$line';
            #d '\n@sub_keys_ordered';
            #d '\n$replaceTable_ref';
            for my $key (@sub_keys_ordered) {
                #d('$key $replaceTable_ref->{$key}'); # Global symbol "$key" requires explicit package name at (eval 15) line 1, <F> line 1
                if ($d) { say "preprocess_file:  key = $key    replaceTable_ref->{$key} = $replaceTable_ref->{$key}" }
                my $cnt;
                if ( $opt{case} ) {
                    $cnt = ( $line =~ s/$key/$replaceTable_ref->{$key}/gi );
                } else {
                    $cnt = ( $line =~ s/$key/$replaceTable_ref->{$key}/g );
                }
                #my $cnt = ($line =~ s/HASH(0x\S+)/$replaceTable_ref->{$key}/g);
                #d("Found $key and replaced with $replaceTable_ref->{$key} on:  $line") if $cnt;
            }
        }

        if ( defined $opt{fieldJustify} ) {
            my $fieldSeparator = decideFieldSeparator($file);
            my $newline        = '';
            chomp $line;
            my @fields = split $fieldSeparator, $line;
            for my $i ( 0 .. $#fields ) {
                $newline .= sprintf( "%-$fieldColumnWidths[$i]s$fieldSeparator", $fields[$i] );
            }
            $line = "$newline\n";
        }

        if ( defined $opt{fields} ) {
            my $fieldSeparator = decideFieldSeparator($file);
            chomp($line);
            my @fields = split /$fieldSeparator/, $line;
            #d '@fields';
            my $newline = '';
            if ($fieldsNegate) {
                for my $i ( 0 .. $#fields ) {
                    if ( $opt{fields} =~ /^$i\+$/ or $opt{fields} =~ /^$i\+,/ or $opt{fields} =~ /,$i\+,/ or $opt{fields} =~ /$i\+$/ ) {
                        last;
                    }
                    if ( $opt{fields} =~ /^$i\+$/ or $opt{fields} =~ /^$i,/ or $opt{fields} =~ /,$i,/ or $opt{fields} =~ /$i$/ ) {
                        # do nothing
                    } else {
                        $newline .= defined $fields[$i] ? "$fields[$i]  " : "";
                    }
                }
            } else {
                for my $f ( split /,/, $opt{fields} ) {
                    #d '$f';
                    if ( $f =~ s/\+$// ) {
                        $newline .= join "  ", @fields[ $f .. $#fields ];
                        last;
                    } else {
                        $newline .= defined $fields[$f] ? "$fields[$f]  " : "";
                    }
                }
            }
            $line = "$newline\n";
        }

        if ( $opt{lsl} ) {
            if ( $line =~ /^total \S+$/ ) {
                #d "Ignoring line because of -lsl option:  $line";
                next;
            }
            if ( $line =~ /(.*)(\S[-rwx]{9})\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+\s+\S+\s+\S+)(\s+\S.*)/ ) {
                my ( $prefix, $perms, $links, $owner, $group, $size, $datetime, $name ) = ( $1, $2, $3, $4, $5, $6, $7, $8 );
                #d "Modifying ls -l line:  $line";
                $line = sprintf( "%sperms links owner group %10d datetime %s\n", $prefix, $size, $name );
            }
        }
        # 'mox1' => HASH(0xa2a540)
        # $fstat = HASH(0x25a5cb0)
        if ( $opt{perlDump} ) {
            $line =~ s/((SCALAR|HASH|ARRAY|REF|GLOB|CODE).*\(.*)\n$/$2()\n/g;    # Perl
            $line =~ s/ at 0x\S+>/>/g;                                           # Python
        }

        if ( $opt{trim} ) {
            chomp( $line = substr( $line, 0, $opt{trim} ) );
            $line .= "\n";
        }

        if ( $opt{filename} ) {
            $line = "$file:$line";
        }

        if ( $opt{length} ) {
            my $length = length($line) - 1;
            $line .= "  ($length characters)\n";
        }

        #d('\n$line');
        print $TMP $line;
    }
    if ( defined $start and not $anyStartFound ) {
        say "WARNING:  Did not find start term '$start' in $tmpfile";
        if ( defined $opt{function} ) {
            say "          You may need to specify option -language to specify the language";
        }
    }
    if ( defined $stop and not $anyStopFound ) {
        say "WARNING:  Did not find stop term '$stop' in $tmpfile";
        if ( defined $opt{function} ) {
            say "          You may need to specify option -language to specify the language";
        }
    }
    close $TMP;
    d( '', 'NC' );    # Turn off line numbers and chomp
    return $tmpfile;
}

sub filesMismatch {
    # Return undef if md5sum of files is identical, list of md5sums if mismatch
    my @fileList = @_;
    my ( $status1, $status2 );
    if ( whichCommand('md5sum') ) {
        # Preferring this method since it's likely faster
        chomp( $status1 = `md5sum '$fileList[0]' | cut -d ' ' -f 1` );
        chomp( $status2 = `md5sum '$fileList[1]' | cut -d ' ' -f 1` );
    } else {
        $status1 = getHash( file => $fileList[0] );
        $status2 = getHash( file => $fileList[1] );
    }
    d '$status1 $status2';
    if ( $status1 ne $status2 ) {
        return ( $status1, $status2 );
    } else {
        return;
    }
}

sub getHash {
    # Get md5sum or xxHash of file
    # Benchmarked using ~/o/perl/dumbbench_getHash.pl
    my %options = @_;
    my $file    = $options{file};
    d '$file';
    if (0) {
        # for testing -report, results are in seconds for small and large directories
        #$getHash{hashingMethod} = 'md5sum';          # 1.5    19
        #$getHash{hashingMethod} = 'Digest::MD5';     # 1.6    17
        #$getHash{hashingMethod} = 'Digest::xxHash';  # 0.9    11.5
        $gui = 'none';
    }
    $getHash{hashingMethod} = 'Digest::MD5';                               # Not using Digest::xxHash because of error "Couldn't open file" on read-only file
    $getHash{hashingMethod} = $options{hash} if defined $options{hash};    # Specify an executable
    if ( !defined $getHash{hashingMethod} ) {
        # Priority is given to Digest::xxHash if it exists for performance reasons, then Digest::MD5, then md5sum
        eval 'use Digest::xxHash ()';
        my $eval_xxHash = $@;
        eval "use File::Map 'map_file'";
        if ( $eval_xxHash || $@ ) {
            eval 'use Digest::MD5 ()';
            if ($@) {
                my $hashingMethod = whichCommand( 'md5sum', 'md5' );       # 'md5' is Apple OS
                if ( defined $hashingMethod ) {
                    $getHash{hashingMethod} = $hashingMethod;
                } else {
                    die "ERROR: Could not determine method for md5sum\n\n";
                }
            } else {
                $getHash{hashingMethod} = 'Digest::MD5';
                $getHash{eval}{'Digest::MD5'} = 1;
            }
        } else {
            $getHash{hashingMethod} = 'Digest::xxHash';
            $getHash{eval}{'Digest::xxHash'} = 1;
        }
    }
    d '$getHash{hashingMethod}';
    my $result = 0;
    if ( defined $opt{hash} ) {
        # -hash <executable>
        die "\nERROR: Executable not found: $opt{hash}\n" unless -f $opt{hash};
        my $cmd = $opt{hash};
        chomp( $result = `$cmd $file 2> /dev/null` );
        $result =~ s/^.*=\s*(\S+)\s*$/$1/;
    } elsif ( $getHash{hashingMethod} eq 'Digest::xxHash' ) {
        if ( !defined $getHash{eval}{'Digest::xxHash'} ) {
            eval 'use Digest::xxHash ()';
            die $@ if $@;
            eval "use File::Map 'map_file'";
            die $@ if $@;
            $getHash{eval}{'Digest::xxHash'} = 1;
        }
        File::Map::map_file( my $data, $file, '+<' );
        $result = Digest::xxHash::xxhash64_hex( $data, undef );
        d '$result';
    } elsif ( $getHash{hashingMethod} eq 'Digest::MD5' ) {
        if ( !defined $getHash{eval}{'Digest::MD5'} ) {
            eval 'use Digest::MD5 ()';
            die $@ if $@;
            $getHash{eval}{'Digest::MD5'} = 1;
        }
        open( my $fh, '<', $file ) or die "Can't open '$file': $!";
        binmode($fh);
        $result = Digest::MD5->new->addfile($fh)->hexdigest;
    } elsif ( $getHash{hashingMethod} eq 'md5sum' ) {
        my $cmd = 'md5sum';
        chomp( $result = `$cmd $file 2> /dev/null` );
        $result =~ s/^(\S+).*/$1/;
    } elsif ( $getHash{hashingMethod} eq 'md5' ) {
        my $cmd = 'md5';
        chomp( $result = `$cmd $file 2> /dev/null` );
        $result =~ s/^.*=\s*(\S+)\s*$/$1/;
    } else {
        die "Program bug!";
    }
    #d '$file $result';
    return $result;
}

# Not used
sub countFilesInDirectory {
    my $dir   = shift;
    my $count = 0;
    File::Find::find( sub { -f and $count++ }, $dir );
    return $count;
}

# $map = readTableFile($filename,$opt{reverse},$opt{regex})
# Reads 2-column table mapping file, returns hash reference, for option -replaceTable
sub readTableFile {
    my ( $table_file, $reverse, $regex ) = @_;
    d '$table_file $reverse $regex';
    my %map;
    say "Reading from table file $table_file" if $opt{replaceTable} and !$opt{quiet};
    my $lineNumber = 0;
    open( my $F, '<', $table_file ) or die "ERROR: Cannot open file for reading:  $table_file\n\n";
    while ( my $line = <$F> ) {
        $lineNumber++;
        #d '$line';
        # __END__
        if ( $line =~ /^__END__$/ ) {
            last;
        }
        # blank line or # comment, but not #!
        if ( $line =~ /^\s*$/ or $line =~ /^\s*#[^!]/ ) {
            # do nothing
        } elsif ( $line =~ /^\s*(\S+)\s+(.*)\n/ ) {    # Allow nothing for value (replace something with nothing, good for removing newlines)
                                                       # search_term    replace_term
                                                       # xtals_in       XTAL_SSIN
            my ( $key, $value ) = ( $1, $2 );
            $value = '' if not $value;
            $value =~ s/\s*$//;
            d "table valid line = $line";
            if ($reverse) {
                if ( defined $map{$value} ) {
                    say "ERROR:  Table file $table_file contains 2 entries for $value in the right column!";
                    say "        1st entry was:  $map{$value}  $value";
                    say "        2nd entry was:  $key  $value  on line $lineNumber";
                    say "Exiting.\n";
                    exit 1;
                } else {
                    $value = ( $regex ? $value : quotemeta($value) );
                    d "reverse value = '$value'    key = '$key'";
                    $map{$value} = eval "qq($key)";
                }
            } else {
                if ( defined $map{$key} ) {
                    say "ERROR:  Table file $table_file contains 2 entries for $key in the left column!";
                    say "        1st entry was:  $key  $map{$key}";
                    say "        2nd entry was:  $key  $value  on line $lineNumber";
                    say "Exiting.\n";
                    exit 1;
                } else {
                    $key = ( $regex ? $key : quotemeta($key) );
                    d "key = '$key'    value = '$value'\n";
                    $map{$key} = eval "qq($value)";
                }
            }
        } else {
            print "ERROR:  Did not understand line in config file:  $line";
            exit 1;
        }
    }
    close $F;
    d '%map';
    return \%map;
}

sub handleSCM {
    my $fileNrev = shift;
    d '$fileNrev';
    if ( $fileNrev !~ m{^\S+:/} and $fileNrev =~ /^([^#]+)(#\d+|#head)?$/ and $fileNrev !~ m{^//} ) {
        # Resolve symbolic link, not just for perforce
        $fileNrev = Cwd::abs_path($1) . ( $2 || '' );
        d '$fileNrev';
    }
    my ( $file, $rev );
    if ( $fileNrev =~ /(\S+)#(\d+|head)$/ ) {
        ( $file, $rev ) = ( $1, $2 );
        $rev = uc($rev) || 'HEAD';
    } elsif ( $fileNrev =~ m{^//} ) {
        $file = $fileNrev;
    } else {
        d 'local file';
        return $fileNrev;
    }
    d '$file $rev';
    if ( 0 and $scm eq 'p4' ) {
        # Print the filelog info for the most current version.  Is this needed?
        my $command1 = "p4 filelog '$fileNrev' | head -n 2 | tail -n 1";
        d '$command1';
        system($command1);
    }
    my $scmTmpFile = sprintf( "$globaltmpdir/%s_%s_%s_p4", basename($0), $$, basename($file) );
    d '$scmTmpFile';
    if ( $scmTmpFile =~ /\.([^\.]+)_p4$/ ) {
        $scmTmpFile =~ s/\.([^\.]+)_p4$/_p4.$1/;    # file.gz_p4 => file_p4.gz
    }
    d '$scmTmpFile $scm';
    my $command2;
    if ( $scm eq 'svn' ) {
        $command2 = "svn cat -r $rev '$file' > $scmTmpFile";
    } elsif ( $scm eq 'p4' ) {
        $command2 = "p4 print -q '$fileNrev' > $scmTmpFile";
        # Work around p4 "Path <path> is not under client's root <path>." issue, which happens because current directory is a soft link ~/s to /home/scratch.ckoknat_cad/ate/scripts
        d '$pwd';
        $command2 = "cd $pwd; $command2";
    } elsif ( $scm eq 'git' ) {
        chomp( my $gitPath = `git ls-files --full-name '$file'` );
        d '$gitPath';
        if ( $gitPath eq '' ) {
            die "ERROR:  Could not get git path of $file\n";
        } else {
            # This only works with the head revision
            $command2 = "git show HEAD:$gitPath > $scmTmpFile";
        }
    } else {
        die "Program bug";
    }
    d '$command2';
    say "Executing  $command2" if $opt{verbose};
    system($command2);
    if ( -z $scmTmpFile ) {
        say "ERROR:  $scm created a file with zero size for $fileNrev\nDoes the $scm fileNrev exist?\nExiting\n";
        exit 1;
    }
    return $scmTmpFile;
}

sub handleScp {
    my $file = shift;
    d '$file';
    my $scpTmpFile = sprintf( "$globaltmpdir/%s_%s_%s_scp", basename($0), $$, basename($file) );
    d '$scpTmpFile';
    if ( $scpTmpFile =~ /\.([^\.]+)_scp$/ ) {
        $scpTmpFile =~ s/\.([^\.]+)_scp$/_scp.$1/;    # file.scp_p4 => file_scp.gz
    }
    d '$scpTmpFile';
    my $cmd = "scp '$file' $scpTmpFile";
    d '$cmd';
    #say "Executing  $cmd" if $opt{verbose};
    say "Executing  $cmd";
    system($cmd);
    if ( -z $scpTmpFile ) {
        say "ERROR:  scp created a file with zero size for $file\nDoes this file exist on the remote host?  Were there login issues?\nExiting\n";
        exit 1;
    }
    return $scpTmpFile;
}

sub indent {
    my $string = shift;
    $string =~ s/^/      /gm;
    $string =~ s/^\s*//;
    return $string;
}

sub sortYamlPerlJson {
    my ( $file, $zipCat, $type ) = @_;
    d '$file $zipCat $type';
    open( my $fh, "$zipCat $file |" ) or die "ERROR: Cannot open file for reading:  $file\n\n";
    local $/ = undef;
    my $data = <$fh>;
    close $fh;
    d '$data';
    my $ref;

    if ( $type eq 'yaml' ) {
        # eval because YAML::XS might not be installed, and Perl < 5.8.1 doesn't support YAML::XS
        eval 'use YAML::XS ()';
        #eval 'use YAML::Syck ()';
        if ($@) {
            say "\n$@\n";
            say "ERROR:  Install YAML::XS from CPAN to use option -yaml";
            say "        sudo cpan install YAML::XS";
            exit 1;
        } else {
            $ref = YAML::XS::Load($data);
            #$ref = YAML::Syck::Load($data);
            d '$ref';
            if ( $opt{removeDictKeys} ) {
                removeDictKeys( $ref, { removeRegex => $opt{removeDictKeys} }, $d );
            }
            if ( $opt{flatten} ) {
                $ref = flatten( $ref, {}, $d );
            }
            if (1) {
                $Data::Dumper::Indent   = 1;    # default = 2, which uses a lot of horizontal space
                $Data::Dumper::Sortkeys = 1;    # produces warning on 5.6.1
                return Dumper($ref);
            } else {
                my $text = YAML::XS::Dump($ref);
                return $text;
            }
        }
    } elsif ( $type eq 'perlEval' ) {
        $ref = eval($data);
        d '$ref';
        $Data::Dumper::Sortkeys = 1;            # produces warning on 5.6.1
        return Dumper($ref);
    } elsif ( $type eq 'json' ) {
        # eval because JSON::XS might not be installed
        eval 'use JSON::XS ()';
        if ($@) {
            say "\n$@\n";
            say "ERROR:  Install JSON::XS from CPAN to use option -json";
            say "        sudo cpan install YAML::XS";
            exit 1;
        } else {
            $ref = JSON::XS::decode_json($data);
            d '$ref';
            if ( $opt{removeDictKeys} ) {
                removeDictKeys( $ref, { removeRegex => $opt{removeDictKeys} }, $d );
            }
            if ( $opt{flatten} ) {
                $ref = flatten( $ref, {}, $d );
            }
            if (1) {
                $Data::Dumper::Indent   = 1;    # default = 2, which uses a lot of horizontal space
                $Data::Dumper::Sortkeys = 1;    # produces warning on 5.6.1
                return Dumper($ref);
            } else {
                my $text = JSON::XS::encode_json($ref);
                return $text;
            }
        }
    } else {
        die;
    }
}

sub getFileType {
    my ($file) = @_;
    d '$file';
    $file =~ s/\.gz$//;
    $file =~ s/#.*//;     # Remove p4 rev number
    ( my $filetype = $file ) =~ s/.*\.//;
    if ( $filetype =~ /yaml/ ) {
        $filetype = 'yml';
    }
    return $filetype;
}

sub getScriptType {
    my %options = @_;
    d '%options';
    my $file = $options{file};
    $file =~ s/#.*//;     # Remove p4 rev number
    my $filetype;
    if ( $file =~ /\.(awk|cpp|go|js|php|r|pl|py|rb|swift|tcl)$/i ) {
        $filetype = lc($1);
        return $filetype;
    } elsif ( $file =~ /\.c$/ ) {
        return 'cpp';
    } elsif ( $file =~ /\.pm$/ ) {
        return 'pl';
    } elsif ( $file =~ /\.tn$/ ) {
        return 'tcl';
    } else {
        # Filename does not have a recognized extension.  Look at the shebang
        if ( -f $file ) {
            chomp( my $line = `grep '^#!' $file | head -n 1` );
            d '$line';
            if ( $line =~ m{^\#!(\S+/env\s+)?(\S+)} ) {
                # #!/usr/bin/python
                # #!/usr/bin/env python
                $filetype = basename($2);
                d '$filetype';
            }
        }
    }
    d '$filetype';
    if ( defined $filetype ) {
        # from shebang
        if ( $filetype =~ /^(node|nodejs)$/ ) {
            return 'js';
        } elsif ( $filetype =~ /^(perl)$/ ) {
            return 'pl';
        } elsif ( $filetype =~ /^(python)[0-9.]*$/ ) {
            return 'py';
        } elsif ( $filetype =~ /^ruby$/ ) {
            return 'rb';
        } elsif ( $filetype =~ /^(tn_shell)$/ ) {
            return 'tcl';
        }
    }
    if ( $options{scriptsOnly} ) {
        return '';
    } else {
        ( $filetype = $file ) =~ s/.*\.//;
        return $filetype;
    }
}

# Written for Python/Perl/TCL, but could be extended to other languages
# As a side effect, this removes blank lines
sub functionSort {
    my ($file) = @_;
    my $language = defined $opt{language} ? $opt{language} : getScriptType( file => $file );
    d '$file $language';
    my %subs;
    my $function = '__MAIN__';
    open( my $F, '<', $file ) or die "ERROR: Cannot open file for reading:  $file\n\n";
    while ( my $line = <$F> ) {
        #d '$function $line';
        if ( $line =~ /^(__END__|__DATA__)/ ) {
            # Perl
            last;
        } elsif ( $line =~ /^\s*$/ ) {
            # Ignore blank lines
        } elsif ( $line =~ /^\s*(#|\/\/)/ ) {
            # Ignore any comments at beginning of line, since function descriptions are often immediately before the function
        } elsif ( $line =~ /^\}/ ) {
            # C / Perl / TCL
            $subs{$function} .= $line;
            $function = '__MAIN__';
        } elsif ( $language !~ /^(js|pl|py|tcl)$/ and $function eq '__MAIN__' and $line =~ /^\s*((unsigned\s+|signed\s+)?(sub|def|proc|function|func|fun|fn|void|int|char|short|long|float|double)\s+([^\s;]+))\s*$/ ) {
            # C and some other languages, this regex is good enough for many cases
            $function = $4;
            $subs{$function} = $line;
        } elsif ( $language eq 'pl' and $line =~ /^\s*(sub\s+(\S+))/ ) {
            # Perl
            $function = $2;
            $subs{$function} = $line;
        } elsif ( $language eq 'py' and $line =~ /^\s*(def\s+(\S+))\s*:/ ) {
            # Python
            $function = $2;
            $subs{$function} = $line;
        } elsif ( $language eq 'tcl' and $line =~ /^\s*(proc\s+(\S+))/ ) {
            # TCL
            $function = $2;
            $subs{$function} = $line;
        } elsif ( $language eq 'js' and $line =~ /^\s*(function\s+(\S+))/ ) {
            # JavaScript
            $function = $2;
            $subs{$function} = $line;
        } else {
            $subs{$function} .= $line;
        }
    }
    d '%subs';
    my $result = '';
    for my $sub ( sort keys %subs ) {
        $result .= "$subs{$sub}\n";
    }
    return $result;
}

# $size = getNumLines("find $file -type f | wc -l");  # number of files in directory
# $size = getNumLines("cat $file");  # number of lines
sub getNumLines {
    my ( $cmd, $options ) = @_;
    if ( !defined $options ) {
        $options = ' -l';
    }
    $cmd = "$cmd | wc $options";
    chomp( my $numLines = `$cmd` );
    $numLines =~ s/^\s+//;    # macOS
    return $numLines;
}

sub whichCommand {
    my @executableAndOptionsArray = @_;
    for my $executableAndOptions (@executableAndOptionsArray) {
        ( my $executable = $executableAndOptions ) =~ s/^(\S+).*/$1/;    # Strip any options before using 'which'
        chomp( my $which = `which $executable 2> /dev/null` );
        return $executableAndOptions if $which ne '';
    }
    return undef;
}

# Convert list to pairs
# 1,2,3,4 -> '1 2', '3 4'
sub pairwise {
    my @items = @_;
    my @pairs;
    while (@items) {
        my $item1 = shift @items;
        my $item2 = shift @items || '';
        push @pairs, "'$item1' '$item2'";    # 'file1' 'file2'
    }
    return @pairs;
}

# Run for case of two directories
sub findFilePairs {
    my ( $dir1, $dir2, $includeRegex, $excludeRegex ) = @_;
    $dir1 =~ s{/$}{};                        # Remove trailing '/' in case user included it, since it affects the next substitution
    $dir2 =~ s{/$}{};
    my @files1 = runFileFind( $dir1, $includeRegex, $excludeRegex );
    my @files2 = runFileFind( $dir2, $includeRegex, $excludeRegex );
    d '$dir1 $dir2 @files1 @files2';
    my ( %filePairDict, @filePairs );
    for my $file1 (@files1) {
        ( my $file = $file1 ) =~ s{^$dir1/}{};
        $filePairDict{$file}[0] = "$dir1/$file";
        $filePairDict{$file}[1] = "$dir2/$file";    # May or may not exist
    }
    for my $file2 (@files2) {
        ( my $file = $file2 ) =~ s{^$dir2/}{};
        $filePairDict{$file}[0] = "$dir1/$file" if !defined $filePairDict{$file}[0];
        $filePairDict{$file}[1] = "$dir2/$file";
    }
    d '%filePairDict';
    for my $file ( sort keys %filePairDict ) {
        push @filePairs, @{ $filePairDict{$file} };
    }
    d '@filePairs';
    return @filePairs;
}

# Run for case of two directories, or -dir2 or -gold
sub runFileFind {
    my ( $dir, $includeRegex, $excludeRegex ) = @_;
    d '$dir $includeRegex $excludeRegex';
    die "\nERROR:  directory $dir does not exist\n" if !-e $dir;
    #$includeRegex =~ s/[^.]\*/.*/g;  # Don't want to use this, because it may corrupt valid Perl regexes
    $includeRegex =~ s/^\*/.*/ if defined $includeRegex;    # *.py to .*.py
    $excludeRegex =~ s/^\*/.*/ if defined $excludeRegex;    # *.pyc to .*.pyc
    my @foundFiles;
    print "Searching recursively in '$dir' for files matching /$includeRegex/" unless $opt{quiet};
    if ( defined $excludeRegex ) {
        print " and not matching /$excludeRegex/" unless $opt{quiet};
    }
    find(
        sub {
            #d '$File::Find::name';
            if ( !-d and $File::Find::name =~ /$includeRegex/ ) {
                if ( defined $excludeRegex ) {
                    if ( $File::Find::name !~ /$excludeRegex/ ) {
                        push @foundFiles, $File::Find::name;
                    } else {
                        # do nothing
                    }
                } else {
                    push @foundFiles, $File::Find::name;
                }
            }
        },
        $dir
    );
    my $numFiles = scalar(@foundFiles);
    if ($numFiles) {
        say "  found $numFiles files" unless $opt{quiet};
    } else {
        say "\nEnsure that the files exist and the -includeFiles <regex> expression '$opt{includeFiles}' is a valid Perl regex (for example use .* instead of *)" unless $opt{quiet};
        exit 0;
    }
    d '@foundFiles';
    return @foundFiles;
}

sub toDir2 {
    my $file = shift;
    # dif file -dir2 otherDir            =>  file            otherDir/file
    # dif dir/file -dir2 otherDir        =>  dir/file        otherDir/dir/file
    # dif /fullPath/file -dir2 otherDir  =>  /fullPath/file  otherDir/file
    my $dir2file;
    if ( $file =~ m{^/} ) {
        $dir2file = "$opt{dir2}/" . basename($file);
    } else {
        $dir2file = "$opt{dir2}/$file";
    }
    return $dir2file;
}

sub toFromGolden {
    my $file = shift;
    my $dir  = dirname($file);
    my ( $goldfile, $position );
    if ( basename($file) =~ /^(.*)\.golden(.*)$/ ) {
        # a.golden     => a
        # a.golden.csv => a.csv
        # returning the NON golden filename
        $goldfile = "$dir/$1$2";
        $position = 2;
    } elsif ( basename($file) =~ /^(.*)(\.[^.]+)$/ ) {
        # a.csv        => a.golden.csv
        # returning the golden filename
        $goldfile = "$dir/$1.golden$2";
        $position = 1;
    } else {
        # a            => a.golden
        # returning the golden filename
        $goldfile = "$file.golden";
        $position = 1;
    }
    return wantarray ? ( $goldfile, $position ) : $goldfile;
}

sub lastScmRev {
    my $base = shift;
    my $lastRev;
    if ( $scms{Perforce} ) {
        chomp( $lastRev = `cd $pwd ; p4 fstat $base | grep headRev | sed 's/.*headRev \\(.*\\)/\\1/'` );
    } elsif ( $scms{SVN} ) {
        chomp( $lastRev = `svn info $base | grep Revision | cut -d " " -f 2` );
    }
    return $lastRev;
}

sub decideFieldSeparator {
    my $file = shift;
    my $fieldSeparator;
    if ( defined $opt{fieldSeparator} ) {
        $fieldSeparator = $opt{fieldSeparator};
    } elsif ( $file =~ /\.csv(\.gz)?$/ ) {
        $fieldSeparator = ',';
    } else {
        $fieldSeparator = '\s+';
    }
    d '$fieldSeparator';
    return $fieldSeparator;
}

sub getFieldColumnWidths {
    my @fieldColumnWidths;
    my @files = @_;
    for my $file (@files) {
        my $fieldSeparator = decideFieldSeparator($file);
        my $zipCat         = extension2zipcat($file);
        open( my $F, "$zipCat $file |" ) or die "ERROR: Cannot open file for reading:  $file\n\n";
        while ( my $line = <$F> ) {
            chomp($line);
            my @fields = split /$fieldSeparator/, $line;
            for my $i ( 0 .. $#fields ) {
                if ( !defined $fieldColumnWidths[$i] or length $fields[$i] > $fieldColumnWidths[$i] ) {
                    $fieldColumnWidths[$i] = length $fields[$i];
                }
            }
            d '@fields';
        }
    }
    d '@fieldColumnWidths';
    return @fieldColumnWidths;
}

sub determineTmpFilename {
    my ( $file, $count ) = @_;
    $count = 0 if !defined $count;
    my $tmpfile = sprintf( "%s/%d__%s", $globaltmpdir, $count, basename($file) );
    $tmpfile =~ s/\s+/_/g;
    $tmpfile =~ s/#/_/g;
    $tmpfile =~ s{/}{\\}g if $windows;
    $tmpfile =~ s/(\.(gz|bz2|xz|Z|zip))//;
    $tmpfile =~ s/\.(tar)/.$1_/;             # Don't want gvimdiff to complain that the tarfile is not valid
    return $tmpfile;
}

sub extension2zipcat {
    # Based on the file extension, select a method for uncompressing the file to stdout
    # Used in this context:
    #     my $zipCat = extension2zipcat($file);
    #     open( $F, "$zipCat $file |" );
    my $file = shift;
    d '$file';
    $file =~ s/(#(\d+|head|\-|\+))?$//;
    $file =~ s/^.*(\.(gz|bz2|xz|Z|zip))$/$1/;
    $file = '.gz' if !defined $file;
    #my %catref = ( '.gz' => 'zcat -c', '.bz2' => 'bzcat -c', '.xz' => 'xzcat -c', '.zip' => 'unzip -cq' );
    my %catref = ( '.gz' => 'gunzip -c', '.bz2' => 'bzcat -c', '.xz' => 'xzcat -c', '.Z' => 'uncompress -c', '.zip' => 'unzip -cq' );
    # macOS issue:  "zcat: can't stat: foo.txt.gz (foo.txt.gz.Z): No such file or directory"
    my $zipCat = $catref{$file};

    if ( !$zipCat ) {
        # .txt
        if ($windows) {
            $zipCat = 'type';
        } else {
            $zipCat = 'cat';
        }
    }
    d '$zipCat';

    if ( whichCommand($zipCat) ) {
        return $zipCat;
    } else {
        die "\nERROR:  Could not find method '$zipCat' to uncompress file format '$file'\n";
    }
}

sub removeDictKeys {
    my ( $hash, $options, $d ) = @_;
    die "Second argument of removeDictKeys() must be an options hash ref!" unless ref($options) && ref($options) eq "HASH";
    if ( ref($hash) eq 'HASH' ) {
        for my $key ( keys %{$hash} ) {
            if ( $options->{keepRegex} ) {
                if ( $key !~ /$options->{keepRegex}/ ) {
                    delete $hash->{$key};
                    next;
                }
            } elsif ( $options->{removeRegex} ) {
                if ( $key =~ /$options->{removeRegex}/ ) {
                    delete $hash->{$key};
                    next;
                }
            }
            if ( ref( $hash->{$key} ) ) {
                if ( ref( $hash->{$key} ) eq "HASH" ) {
                    removeDictKeys( $hash->{$key}, $options );
                } elsif ( ref( $hash->{$key} ) eq "ARRAY" ) {
                    removeDictKeys( $hash->{$key}, $options );
                } else {
                    # do nothing for reference to scalar or other
                }
            } else {
                # do nothing for scalar
            }
        }
    } elsif ( ref($hash) eq 'ARRAY' ) {
        for my $n ( 0 .. scalar @{$hash} - 1 ) {
            if ( $options->{keepRegex} ) {
                if ( $hash->[$n] !~ /$options->{keepRegex}/ ) {
                    if ( ref( $hash->[$n] ) or $options->{removeArrayElements} ) {
                        delete $hash->[$n];
                        next;
                    }
                }
            } elsif ( $options->{removeRegex} ) {
                if ( $hash->[$n] =~ /$options->{removeRegex}/ ) {
                    if ( ref( $hash->[$n] ) or $options->{removeArrayElements} ) {
                        delete $hash->[$n];
                        next;
                    }
                }
            }
            if ( ref( $hash->[$n] ) ) {
                if ( ref( $hash->[$n] ) eq "HASH" ) {
                    removeDictKeys( $hash->[$n], $options );
                } elsif ( ref( $hash->[$n] ) eq "ARRAY" ) {
                    removeDictKeys( $hash->[$n], $options );
                } else {
                    # do nothing for reference to scalar or other
                }
            } else {
                # do nothing for scalar
            }
        }
    } else {
        die "First argument of removeDictKeys() must be a hash or array ref!" unless ref($hash);
    }
}

sub flatten {
    my ( $hash, $options, $d ) = @_;
    die "Second argument of removeDictKeys() must be an options hash ref!" unless ref($options) && ref($options) eq "HASH";
    eval 'use Hash::Flatten ()';
    if ($@) {
        say "\n$@\n";
        say "ERROR:  Install Hash::Flatten from CPAN to flatten yml and json files";
        say "        sudo cpan install Hash::Flatten";
        exit 1;
    } else {
        my $o = new Hash::Flatten(
            {
                # These pseudo-options can be defined in the ~/.dif.defaults file
                HashDelimiter  => defined $opt{hashDelimiter}  ? $opt{hashDelimiter}  : '/',
                ArrayDelimiter => defined $opt{arrayDelimiter} ? $opt{arrayDelimiter} : '/',
                OnRefScalar    => 'warn',
            }
        );
        return $o->flatten($hash);
    }
}

__END__

dif by Chris Koknat  https://github.com/koknat/dif
v100 Fri Nov  4 10:15:57 PDT 2022


This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details:
<http://www.gnu.org/licenses/gpl.txt>

