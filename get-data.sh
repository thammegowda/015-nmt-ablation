#!/usr/bin/env bash

#SBATCH --partition=xxx
#SBATCH --mem=20G
#SBATCH --time=0-10:00:00
#SBATCH --nodes=1 --ntasks=1
#SBATCH --cpus-per-task=20
#SBATCH --gres=gpu:0
#SBATCH --output=R-%x.out.%j
#SBATCH --error=R-%x.err.%j
#SBATCH --export=NONE

set -eu

#source ~/.bashrc
#conda deactivate
#conda activate fairseq

ROOT=$PWD
DATA=$ROOT/data

log() { printf "$(date --rfc-3339 s): $1\n"; }
exit_log() { log "$2";  exit $1; }

N_CPU=20

# check requirements
# pip install nlcodec mtdata==0.3 or newer

for lib in  mtdata sacremoses awkg; do
    which $lib > /dev/null || exit_log 1 "$lib required but not found"
done
# indic-nlp-library broke CLI interface in new versions
python -m indicnlp.tokenize.indic_tokenize <(echo test) /dev/null hi || exit_log 1 'pip install indic-nlp-library==0.6' 


clean_parallel() {

awkg -F '\t' -b 'from html import unescape; goods, bads = 0, 0' '
good = len(R) == 2
if good:
  src = R[0].strip()
  tgt = R[1].strip()
  good = good and "http" not in src and "http" not in tgt
  src = unescape(src).split()
  tgt = unescape(tgt).split()
  good = good and 1 <= len(src) <= 512 and 1 <= len(tgt) <= 512
  good = good and 1/5 <= len(src)/len(tgt) <= 5
  good = good and max(len(w) for w in src + tgt) < 30

if good:
   goods += 1
   print(" ".join(src), " ".join(tgt))
else:
   bads += 1

# if not good: # print bad
#  print(R0)
' -e 'sys.stderr.write(f"good={goods:,} bad={bads:,} records")'

}

deen=$DATA/deu-eng
# Step download mtdata
[[ -f $deen/_OK ]] && log "Skip deu-eng; rm $deen/_OK to force" || {
    [[ -f $deen/mtdata.signature.txt ]] \
	|| mtdata get -l deu-eng \
	          -tr Statmt-{europarl-9,commoncrawl_wmt13-1,news_commentary-14}-deu-eng \
	          -ts Statmt-newstest_ende-20{18,19,20}-eng-deu Statmt-newstest_deen-20{14,18,19,20}-deu-eng  \
	          -o $deen --merge \
	|| exit_log 1 "download failed"

    # move these as orig, make place for cleaned
    [[ -f $deen/train.eng ]] && mv $deen/train.eng{,.orig}
    [[ -f $deen/train.deu ]] && mv $deen/train.deu{,.orig}

    printf "de deu\nen eng\n" | while read iso2 lang; do
	for f in $deen/train.$lang.orig $deen/tests/*.$lang; do
	    [[ -f $f.tok  && "$(wc -l < $f)" -eq "$(wc -l < $f.tok)" ]] && continue
	    log "tokenize: $f -> $f.tok"
	    sacremoses -l $iso2 -j $N_CPU tokenize -x < $f > $f.tok || exit_log 1 "tokenization fail"
	done
    done

    [[ -f $deen/train.deu-eng.cln.tok ]] || paste $deen/train.{deu,eng}.orig.tok | clean_parallel  > $deen/train.deu-eng.cln.tok
    cut -f1 $deen/train.deu-eng.cln.tok > $deen/train.all.deu.tok
    cut -f2 $deen/train.deu-eng.cln.tok > $deen/train.all.eng.tok


    log "shuffling and preparing subsets"
    cat $deen/train.deu-eng.cln.tok | shuf --random-source=$deen/train.eng.orig > $deen/train-shuf.all.deu-eng.tok

    printf "030k 30000\n500k 500000\n001m 1000000\n" | while read name size; do
	cut -f1 $deen/train-shuf.all.deu-eng.tok | head -$size > $deen/train.$name.deu.tok
	cut -f2 $deen/train-shuf.all.deu-eng.tok | head -$size > $deen/train.$name.eng.tok
    done
 
    touch $deen/_OK 
}


hien=$DATA/hin-eng

[[ -f $hien/_OK ]] && log "Skip hin-eng; rm $hien/_OK to force" || {
    [[ -f $hien/mtdata.signature.txt ]] \
	|| mtdata get -l hin-eng \
	          -tr IITB-hien_train-1.5-hin-eng \
                  -dv IITB-hien_dev-1.5-hin-eng \
                  -ts IITB-hien_test-1.5-hin-eng  \
	          -o $hien --merge \
	|| exit_log $1 "hin-eng download failed"

    # move these as orig, make place for cleaned
    [[ -f $hien/train.eng ]] && mv $hien/train.eng{,.orig}
    [[ -f $hien/train.hin ]] && mv $hien/train.hin{,.orig}
    
    # ennglish using sacremoses, -x is for dont escape XML chars
    for f in $hien/train.eng.orig $hien/{dev,test1}.eng $hien/tests/*.eng; do
	[[ -f $f.tok  && "$(wc -l < $f)" -eq "$(wc -l < $f.tok)" ]] && continue
	log "tokenize: $f -> $f.tok"
	sacremoses -l en -j $N_CPU tokenize -x < $f > $f.tok || exit_log 1 "tokenization fail"
    done
    
    for f in $hien/train.hin.orig $hien/{dev,test1}.hin $hien/tests/*.hin; do
	[[ -f $f.tok  && "$(wc -l < $f)" -eq "$(wc -l < $f.tok)" ]] && continue
	log "tokenize: $f -> $f.tok"
	python -m indicnlp.tokenize.indic_tokenize $f $f.tok hi || exit_log 1 "tokenization fail"
    done


    [[ -f $hien/_CLNd ]] || {
	log "Clearning and deduping "
	paste $hien/train.{hin,eng}.orig.tok | clean_parallel  | sort | uniq > $hien/train.hin-eng.cln.tok
	cut -f1 $hien/train.hin-eng.cln.tok > $hien/train.all.hin.tok
	cut -f2 $hien/train.hin-eng.cln.tok > $hien/train.all.eng.tok
	touch $hien/_CLNd
    }


    log "shuffling and preparing subsets"
    cat $hien/train.hin-eng.cln.tok | shuf --random-source=$hien/train.eng.orig > $hien/train-shuf.all.hin-eng.tok

    printf "030k 30000\n500k 500000\n001m 1000000\n" | while read name size; do
	cut -f1 $hien/train-shuf.all.hin-eng.tok | head -$size > $hien/train.$name.hin.tok
	cut -f2 $hien/train-shuf.all.hin-eng.tok | head -$size > $hien/train.$name.eng.tok
    done
    touch $hien/_OK 
}



#mtdat get -l lt-en -tr europarl_v10 wiki_titles_v1 paracrawl_v6 EESC2017 EMA2016 airbaltic ecb2017 rapid2016 -ts newsdev2019_lten newstest2019_lten
lten=$DATA/lit-eng

[[ -f $lten/_OK ]] && log "Skip hin-eng; rm $lten/_OK to force" || {
    [[ -f $lten/mtdata.signature.txt ]] \
	|| mtdata get -l lit-eng \
	          -tr Statmt-europarl-10-lit-eng \
                  -ts Statmt-news{dev,test}_enlt-2019-eng-lit Statmt-news{dev,test}_lten-2019-lit-eng \
	          -o $lten --merge \
	|| exit_log $1 "lit-eng download failed"

    # move these as orig, make place for cleaned
    [[ -f $lten/train.eng ]] && mv $lten/train.eng{,.orig}
    [[ -f $lten/train.lit ]] && mv $lten/train.lit{,.orig}
    
    printf "lt lit\nen eng\n" | while read iso2 lang; do
	for f in $lten/train.$lang.orig $lten/tests/*.$lang; do
	    [[ -f $f.tok  && "$(wc -l < $f)" -eq "$(wc -l < $f.tok)" ]] && continue
	    log "tokenize: $f -> $f.tok"
	    sacremoses -l $iso2 -j $N_CPU tokenize -x < $f > $f.tok || exit_log 1 "tokenization fail"
	done
    done

    [[ -f $lten/train.lit-eng.cln.tok ]] || paste $lten/train.{lit,eng}.orig.tok | clean_parallel  > $lten/train.lit-eng.cln.tok
    cut -f1 $lten/train.lit-eng.cln.tok > $lten/train.all.lit.tok
    cut -f2 $lten/train.lit-eng.cln.tok > $lten/train.all.eng.tok

    log "shuffling and preparing subsets"
    cat $lten/train.lit-eng.cln.tok | shuf --random-source=$lten/train.eng.orig > $lten/train-shuf.all.lit-eng.tok

    printf "030k 30000\n500k 500000\n001m 1000000\n" | while read name size; do
	cut -f1 $lten/train-shuf.all.lit-eng.tok | head -$size > $lten/train.$name.lit.tok
	cut -f2 $lten/train-shuf.all.lit-eng.tok | head -$size > $lten/train.$name.eng.tok
    done
 
    touch $lten/_OK 
}
