#!/usr/bin/env bash
# Stand-in for SPAdes, used only so demo/record.sh has a real (short-lived)
# assembly step to run without depending on real bioinformatics tools.
set -euo pipefail

outdir="assembly"
prev=""
for arg in "$@"; do
  if [ "$prev" = "-o" ]; then
    outdir="$arg"
  fi
  prev="$arg"
done
mkdir -p "$outdir"

echo " === Assembling started ==="
sleep 0.25
echo "0:00:01   1G / 1G   INFO   General   (main.cpp:100)   K-mer counting"
sleep 0.25
echo "0:00:03   1G / 1G   INFO   General   (main.cpp:150)   Repeat resolution"
sleep 0.25

printf '>NODE_1_length_128531_cov_42.7\nACGTACGTACGTACGTACGTACGTACGTACGT\n' > "$outdir/scaffolds.fasta"
printf '>NODE_1_length_128531_cov_42.7\nACGTACGTACGTACGTACGTACGTACGTACGT\n' > "$outdir/contigs.fasta"

echo " === Assembling finished ==="
echo "Assembly written to ${outdir}/scaffolds.fasta"
