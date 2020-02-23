#!/usr/bin/env nextflow
dbin = "$baseDir/scripts"
lphbin = "$baseDir/data-fingerprints"

/* parameter defaults */
params.infile = "$baseDir/test/test_data.txt"
params.format = 'table'
params.docket = "$baseDir/test/test_data.docket"
params.L = 500
params.histL = 50
params.minTriples = 1
params.skipDuplicates = 1
params.rowclusters = 3
params.colclusters = 3

/* interpret parameters */
infile = file(params.infile)
docket = file(params.docket)
L = params.L
histL = params.histL


/* SECTION: preparation */
process ingest_file {
	/* read the file, store contents as row-wise and column-wise json */
	/* temporary: keeping only the first instance (row) for each id */
	publishDir "$docket/data", mode: 'copy'
	input: file infile
	output:
		file 'cols_data.json.gz' into colsdata
		file 'rows_data.json.gz' into rowsdata
	"""
	${dbin}/ingest.pl $infile $params.format $params.skipDuplicates
	"""
}
/* END SECTION: preparation */



/* SECTION: column histogram pipeline */
process column_histograms {
	/* column-wise histograms of observed values */
	publishDir "$docket/data", mode: 'copy'
	input: file cd from colsdata
	output: file 'cols_hist.json.gz' into colshist
	output: file 'cols_types.json.gz' into colstypes
	"""
	$dbin/compute_hist.pl $cd cols_hist.json cols_types.json
	gzip cols_hist.json cols_types.json
	"""
}
process compute_col_hist_fingerprints {
	/* compute and serialize fingerprints of column-wise histograms of observed values */
	publishDir "$docket/fingerprints", mode: 'copy'
	input: file ch from colshist
	output: file 'cols_hist_fp.trim.gz' into colshistfp
	output: file 'cols_hist_fp.fp' into colshistfpser
	output: file 'cols_hist_fp.id' into colshistfpserids
	"""
	$dbin/compute_fp.pl $ch $histL | gzip -c > cols_hist_fp.raw.gz
	$dbin/filterTable.pl cols_hist_fp.raw.gz 1 $params.minTriples | gzip -c > cols_hist_fp.trim.gz
	$lphbin/serializeLPH.pl cols_hist_fp $histL 1 1 cols_hist_fp.trim.gz
	"""
}
process PCA_col_hist_fingerprints {
	/* compute PCA on fingerprints of column histograms */
	publishDir "$docket/analyses", mode: 'copy'
	input: file chfp from colshistfp
	output: file 'cols_hist_fp.pca.gz' into colshistfppca
	"""
	$dbin/pca.py $chfp --L $histL | gzip -c > cols_hist_fp.pca.gz
	"""
}
process plot_PCA_col_hist_fingerprints {
	/* plot PC1-PC2 on fingerprints of column histograms */
	publishDir "$docket/visualizations", mode: 'copy'
	input: file chfp from colshistfppca
	output: file 'cols_hist_fp.pc1_pc2.pdf'
	"""
	$dbin/plotpca.py $chfp cols_hist_fp.pc1_pc2.pdf
	"""
}
process compare_col_hist_fingerprints {
	/* compare fingerprints of column-wise histograms of observed values */
	publishDir "$docket/comparisons", mode: 'copy'
	input: file chf from colshistfpser
	output: file 'cols_hist_fp.aaa.gz' into chfaaa
	output: file 'cols_hist_fp.aaa.hist' into chfaaahist
	"""
	$lphbin/searchLPHs.pl $chf 0 1000000 cols_hist_fp.aaa.hist | gzip -c > cols_hist_fp.aaa.gz
	"""
}
process index_col_hist_fingerprints {
	/* index fingerprints of column-wise histograms, using annoy */
	errorStrategy 'ignore'
	publishDir "$docket/fingerprints", mode: 'copy'
	input: file chf from colshistfp
	output: file 'cols_hist_fp.tree' into colshistfpindex
	output: file 'cols_hist_fp.names' into colshistfpnames
	"""
	$dbin/annoyIndexGz.py --file $chf --L $histL --norm 1 --out cols_hist_fp
	"""
}
process KNN_col_hist_fingerprints {
	/* find k nearest neighbors of column-wise histograms, using annoy */
	errorStrategy 'ignore'
	publishDir "$docket/comparisons", mode: 'copy'
	input: file chfi from colshistfpindex
	input: file chfn from colshistfpnames
	output: file 'cols_hist_fp.knn.gz'
	"""
	$dbin/annoyQueryAll.py --index $chfi --names $chfn --L $histL --k 100 | gzip -c > cols_hist_fp.knn.gz
	"""
}
/* END SECTION: column histogram pipeline */



/* SECTION: row histogram pipeline */
process row_histograms {
	/* row-wise histograms of observed values */
	publishDir "$docket/data", mode: 'copy'
	input: file rd from rowsdata
	output: file 'rows_hist.json.gz' into rowshist
	output: file 'rows_types.json.gz' into rowstypes
	"""
	$dbin/compute_hist.pl $rd rows_hist.json rows_types.json
	gzip rows_hist.json rows_types.json
	"""
}
/* END SECTION: row histogram pipeline */



/* SECTION: row analysis pipeline */
process compute_row_fingerprints {
	/* row-wise fingerprints */
	publishDir "$docket/fingerprints", mode: 'copy'
	input: file rd from rowsdata
	output: file 'rows_allfp.raw.gz' into rowsallfp
	"""
	$dbin/compute_fp.pl $rd $L | gzip -c > rows_allfp.raw.gz
	"""
}
process trim_row_fingerprints {
	/* trim row-wise fingerprints by triples */
	publishDir "$docket/fingerprints", mode: 'copy'
	input: file rfp from rowsallfp
	output: file 'rows_fp.raw.gz' into rowstrimfp
	"""
	$dbin/filterTable.pl $rfp 1 $params.minTriples | gzip -c > rows_fp.raw.gz
	"""
}
process center_row_fingerprints {
	/* center row-wise fingerprints */
	publishDir "$docket/fingerprints", mode: 'copy'
	input: file rfp from rowstrimfp
	output: file 'rows_fp.cent.gz' into rowscentfp
	"""
	gunzip -c $rfp | $dbin/center_fp.pl | gzip -c > rows_fp.cent.gz
	"""
}
process serialize_cent_row_fingerprints {
	/* serialize centered row-wise fingerprints */
	publishDir "$docket/fingerprints", mode: 'copy'
	input: file rfp from rowscentfp
	output: file 'rows_fp.fp' into rowsfp
	output: file 'rows_fp.id' into rowsfpids
	"""
	$lphbin/serializeLPH.pl rows_fp $L 1 0 $rfp
	"""
}
process PCA_row_fingerprints {
	/* compute PCA on fingerprints of rows */
	publishDir "$docket/analyses", mode: 'copy'
	input: file rfp from rowscentfp
	output: file 'rows_fp.pca.gz' into rowsfppca
	"""
	$dbin/pca.py $rfp --L $L | gzip -c > rows_fp.pca.gz
	"""
}
process compare_row_fingerprints {
	/* compare fingerprints of rows */
	publishDir "$docket/comparisons", mode: 'copy'
	input: file rfp from rowsfp
	output: file 'rows_fp.aaa.gz' into rowsaaa
	output: file 'rows_fp.aaa.hist' into rowsaaahist
	"""
	$lphbin/searchLPHs.pl $rfp 0 1000000 rows_fp.aaa.hist | gzip -c > rows_fp.aaa.gz
	"""
}
process index_row_fingerprints {
	/* index fingerprints of rows, using annoy */
	errorStrategy 'ignore'
	publishDir "$docket/fingerprints", mode: 'copy'
	input: file rfp from rowscentfp
	output: file 'rows_fp.tree' into rowsfpindex
	output: file 'rows_fp.names' into rowsfpnames
	"""
	$dbin/annoyIndexGz.py --file $rfp --L $L --norm 1 --out rows_fp
	"""
}
process KNN_row_fingerprints {
	/* find k nearest neighbors of rows, using annoy */
	errorStrategy 'ignore'
	publishDir "$docket/comparisons", mode: 'copy'
	input: file rfpi from rowsfpindex
	input: file rfpn from rowsfpnames
	output: file 'rows_fp.knn.gz'
	"""
	$dbin/annoyQueryAll.py --index $rfpi --names $rfpn --L $L --k 100 | gzip -c > rows_fp.knn.gz
	"""
}
process row_cluster_hier {
    /* Compute row-wise clustering */
    publishDir "$docket/analyses", mode: 'copy'
    input: file rpca from rowsfppca
    output: file 'rows_hier_clusters.txt.gz' into rows_hier_clust
    """
    $dbin/hierarchical_clustering.py --source $rpca | gzip -c > rows_hier_clusters.txt.gz
    """
}
process plot_PCA_row_fingerprints {
	/* plot PC1-PC2 on fingerprints of rows */
	publishDir "$docket/visualizations", mode: 'copy'
	input: file pca from rowsfppca
	input: file rhc from rows_hier_clust
	output: file 'rows_fp.pc1_pc2.pdf'
	"""
	$dbin/plotpca.py $pca rows_fp.pc1_pc2.pdf --clustering $rhc --clusters $params.rowclusters
	"""
}
/* END SECTION: row analysis pipeline */


/* SECTION: column analysis pipeline */
process compute_col_fingerprints {
	/* col-wise fingerprints */
	publishDir "$docket/fingerprints", mode: 'copy'
	input: file cd from colsdata
	output: file 'cols_allfp.raw.gz' into colsallfp
	"""
	$dbin/compute_fp.pl $cd $L | gzip -c > cols_allfp.raw.gz
	"""
}
process trim_col_fingerprints {
	/* trim col-wise fingerprints by triples */
	publishDir "$docket/fingerprints", mode: 'copy'
	input: file cfp from colsallfp
	output: file 'cols_fp.raw.gz' into colstrimfp
	"""
	$dbin/filterTable.pl $cfp 1 $params.minTriples | gzip -c > cols_fp.raw.gz
	"""
}
process center_col_fingerprints {
	/* center col-wise fingerprints */
	publishDir "$docket/fingerprints", mode: 'copy'
	input: file cfp from colstrimfp
	output: file 'cols_fp.cent.gz' into colscentfp
	"""
	gunzip -c $cfp | $dbin/center_fp.pl | gzip -c > cols_fp.cent.gz
	"""
}
process serialize_cent_col_fingerprints {
	/* serialize centered col-wise fingerprints */
	publishDir "$docket/fingerprints", mode: 'copy'
	input: file cfp from colscentfp
	output: file 'cols_fp.fp' into colsfp
	output: file 'cols_fp.id' into colsfpids
	"""
	$lphbin/serializeLPH.pl cols_fp $L 1 1 $cfp
	"""
}
process PCA_col_fingerprints {
	/* compute PCA on fingerprints of columns */
	publishDir "$docket/analyses", mode: 'copy'
	input: file cfp from colscentfp
	output: file 'cols_fp.pca.gz' into colsfppca
	"""
	$dbin/pca.py $cfp --L $L | gzip -c > cols_fp.pca.gz
	"""
}
process compare_col_fingerprints {
	/* compare fingerprints of columns */
	publishDir "$docket/comparisons", mode: 'copy'
	input: file cfp from colsfp
	output: file 'cols_fp.aaa.gz' into colsaaa
	output: file 'cols_fp.aaa.hist' into colsaaahist
	"""
	$lphbin/searchLPHs.pl $cfp 0 1000000 cols_fp.aaa.hist | gzip -c > cols_fp.aaa.gz
	"""
}
process index_col_fingerprints {
	/* index fingerprints of columns, using annoy */
	errorStrategy 'ignore'
	publishDir "$docket/fingerprints", mode: 'copy'
	input: file cfp from colscentfp
	output: file 'cols_fp.tree' into colsfpindex
	output: file 'cols_fp.names' into colsfpnames
	"""
	$dbin/annoyIndexGz.py --file $cfp --L $L --norm 1 --out cols_fp
	"""
}
process KNN_col_fingerprints {
	/* find k nearest neighbors of columns, using annoy */
	errorStrategy 'ignore'
	publishDir "$docket/comparisons", mode: 'copy'
	input: file cfpi from colsfpindex
	input: file cfpn from colsfpnames
	output: file 'cols_fp.knn.gz'
	"""
	$dbin/annoyQueryAll.py --index $cfpi --names $cfpn --L $L --k 100 | gzip -c > cols_fp.knn.gz
	"""
}
process col_cluster_hier {
    /* Compute col-wise clustering */
    publishDir "$docket/analyses", mode: 'copy'
    input: file cpca from colsfppca
    output: file 'cols_hier_clusters.txt.gz' into cols_hier_clust
    """
    $dbin/hierarchical_clustering.py --source $cpca | gzip -c > cols_hier_clusters.txt.gz
    """
}
process plot_PCA_col_fingerprints {
	/* plot PC1-PC2 on fingerprints of columns */
	publishDir "$docket/visualizations", mode: 'copy'
	input: file pca from colsfppca
	input: file chc from cols_hier_clust
	output: file 'cols_fp.pc1_pc2.pdf'
	"""
	$dbin/plotpca.py $pca cols_fp.pc1_pc2.pdf --clustering $chc --clusters $params.colclusters
	"""
}
process compute_numeric_associations {
	/* compute pairwise Spearman correlations between numerical columns */
	publishDir "$docket/comparisons", mode: 'copy'
	input: file ctypes from colstypes
	output: file 'num_assoc.gz'
	"""
	$dbin/numerical_associations.py --infile $params.infile --types_file $ctypes --header_row 0 --index_col 0 | gzip -c > num_assoc.gz
	"""
}
process compute_categorical_associations {
	/* compute pairwise Cramer V and Theil's U between categorical columns */
	publishDir "$docket/comparisons", mode: 'copy'
	input: file ctypes from colstypes
	output: file 'cat_assoc.gz'
	"""
	$dbin/categorical_associations.py --infile $params.infile --types_file $ctypes --header_row 0 --index_col 0 | gzip -c > cat_assoc.gz
	"""
}

/* END SECTION: column analysis pipeline */


/* ENRICHMENT ANALYSIS */

process row_cluster_hier_v2 {
    /* Compute row-wise clustering */
    publishDir "$docket/analyses", mode: 'copy'

    input:
    file rpca from rowsfppca

    output:
    file 'cluster_labels.txt.gz' into rows_hclust_labels
    file 'cluster_members.json.gz' into rows_hclust_members

    """
    $dbin/cluster_hier.py \
      --source $rpca \
      --cl_labels_out cluster_labels.txt.gz \
      --cl_members_out cluster_members.json.gz
    """
}

process pairwise_occurrence_counts {
    /* Get occurrence counts for all attributes and parent/children trios for branch points in cluster hierarchy */
    publishDir "$docket/analyses", mode: 'copy'

    input:
    file cdata from colsdata
    file rhc_members from rows_hclust_members

    output:
    file 'pairwise_occurrence_counts.json.gz' into occur_counts

    """
    $dbin/pairwise_occurrence_counts.py \
      --source $cdata \
      --cluster_members $rhc_members \
      --counts_out pairwise_occurrence_counts.json.gz
    """
}
