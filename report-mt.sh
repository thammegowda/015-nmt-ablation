#!/usr/bin/env bash

# with macroBLEU and macroF1 support
#export PYTHONPATH=/home/07394/tgowda/repos/sacre-BLEU
## <script.sh> exp1 exp2 exp3 ...

MOSES=$(echo ~/work1/repos/mosesdecoder)

log_exit() {
    "log_exit <exitcode> <log message>"
    printf "$2\n" >&2 
    exit $1
}

[[ $# -eq 0 ]] && log_exit 1 "Usage:: ./report-mt.sh <exp1> <exp2> <exp3>\n
   <exp1> ... positional args are path to experiment dirs"

MOSES_TOKR=$MOSES/scripts/tokenizer/tokenizer.perl
MOSES_DETOKR=$MOSES/scripts/tokenizer/detokenizer.perl
MULTI_BLEU=$MOSES/scripts/generic/multi-bleu.perl
[[ -d $MOSES ]] || log_exit 1 "mosesrecoder repo at $MOSES not found"
[[ -f $MOSES_TOKR ]] || og_exit 1 "$MOSES_TOKR not found"

#LC="-lc"
LC=""

function sacre_bleu {
    hyp=$1
    ref=$2
    if [[ ! -f $hyp ]]; then
        echo "NA-hyp"
    elif [[ ! -f $ref ]]; then
         echo "NA-ref"
    else
        echo $(cut -f1 $hyp | sed 's/<unk>//g' | python -m sacrebleu --force -m bleu -b $LC $ref)
    fi
}

function tok_bleu {
    # this is non-standard; But WAT21 organizers have done this so I am trying to match it
    hyp=$1
    ref=$2
    tok=$3 
    if [[ ! -f $hyp ]]; then
        echo "NA-hyp"
    elif [[ ! -f $ref ]]; then
         echo "NA-ref"
    elif [[  $tok != "moses" ]]; then  # TODO: support more tokenizers
        echo "unknown-tok"
    else
        tok=$MOSES_TOKR
        score=$(cut -f1 $hyp |
            sed 's/<unk>//g' |
            ${tok} 2> /dev/null |
            $MULTI_BLEU 2> /dev/null <(${tok} < $ref 2> /dev/null) |
            sed 's/,//g' | awk '{print $3}' )
        echo $score
    fi
}

function macro_f1 {
    hyp=$1
    ref=$2
    if [[ ! -f $hyp ]]; then
        echo "NA-hyp"
    elif [[ ! -f $ref ]]; then
         echo "NA-ref"
    else
        echo $(cut -f1 $hyp | sed 's/<unk>//g' | python -m sacrebleu -m macrof -w 1 -b $LC  $ref)
    fi
}

function sacre_chrf {
    hyp=$1
    ref=$2
    if [[ ! -f $hyp ]]; then
        echo "NA-hyp"
    elif [[ ! -f $ref ]]; then
         echo "NA-ref"
    elif [[  $tok != "moses" ]]; then  # TODO: support more tokenizers
        echo "unknown-tok"
    else
        echo $(cut -f1 $hyp | sed 's/<unk>//g' | python -m sacrebleu -m chrf -b $LC $ref)
    fi
}

delim=${delim:-','} #delim='\t'
# extract test names automatically
names=$(for i in ${@}; do
            [[ -d $(echo $i/test_*) ]] || continue;
            for j in ${i}/test_*/*.ref ; do basename $j; done
        done | sed 's/.ref$//' | sort -n | uniq)
#names="dev test1"
names_str=$(echo $names | sed "s/ /$delim/g")

#echo "Reporting BLEU, MacroF1,CHRF2 with $LC detok"
printf "Experiment${delim}Metric${delim}${names_str}\n"
#printf "Experiment${delim}BLEU:${names_str}${delim}MacroF1:${names_str}${delim}CHRF2:${names_str}\n"
for d in ${@}; do
    for td in $d/test_*; do
        bleus=""
        macfs=""
        chrfs=""
        tokbleus=""
        for t in $names; do
            hyp_detok=${td}/$t.out.detok
            ref=${td}/$t.ref
            bleus+=$delim$(sacre_bleu $hyp_detok $ref)
            #tokbleus+=$delim$(tok_bleu $hyp_detok $ref "moses")
	    macfs+=$delim$(macro_f1 $hyp_detok $ref)
            #chrfs+=$delim$(sacre_chrf $hyp_detok $ref)
            #printf "${delim}${bleu_score}${delim}${macf_score}${delim}${chrf_score}"
            #printf "${delim}${chrf_score}"
        done
        #echo "$td${bleus}${tokbleus}"
        echo "$td${delim}BLEU${bleus}"
        echo "$td${delim}MacF${macfs}"
        #echo "$td${bleus}${macfs}${chrfs}"
    done
    #printf "\n"
done
