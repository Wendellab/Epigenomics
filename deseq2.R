######################################
## Differential Expression Analysis ##
######################################

# generate read ount table from htseq-count results
setwd("/home/hugj2006/ML/htseq_count")
files<-grep(".namesort.bam.txt",list.files(),value=TRUE)
for(f in files)
{
    x <- read.table(f,sep="\t")
    names(x) <- c("gene", gsub(".namesort.bam.txt","",f))
    if(!exists("allcount")) {allcount = x}
    else {allcount <- merge(allcount, x, by="gene")}
}
write.table(allcount, file="count.raw.txt", row.names=FALSE, sep="\t")


allcount<-read.table(file="count.raw.txt", header=TRUE, sep="\t")
row.names(allcount) <- allcount$gene
count13<-allcount[grep("Gorai.0",allcount$gene,value=TRUE),-1]
dim(count13) # 37223    47

# prepare column information table
coldata<- as.data.frame(t(allcount[grep("__",allcount$gene,value=TRUE),-1]))
coldata$sample<-rownames(coldata)
coldata$flowering <-"F"
coldata$flowering[grep("NF",coldata$sample)] <-"NF"
coldata$condition<-gsub("[.].*","",rownames(coldata))
coldata$sample<-gsub("[.]S.*|[.]L.*","",coldata$sample)
coldata$genome<-gsub(".*[.]","",coldata$sample)

# prepare for exploratory plots
library(genefilter)
sumPCA<-
function (x, genes, intgroup = "condition", ntop = 500)
{
    rv = rowVars(assay(x)[genes,])
    select = order(rv, decreasing = TRUE)[seq_len(min(ntop, length(rv)))]
    pca = prcomp(t(assay(x)[genes,][select, ]))
    tt = pca$x[,c("PC1","PC2")]
    tt = cbind(tt, coldata[rownames(tt),] )
    attr(tt,"percentVar")<-summary(pca)$importance[2,1:2]
    return(tt)
}
# consider flowering time genes from Corrinne
ftgenes<-as.character(read.table("~/ML/floweringtime.genes")$V1 )
library(DESeq2)
library(ggplot2)
dds <- DESeqDataSetFromMatrix( countData = count13, colData = coldata, design = ~ sample)
rld <- rlog(dds, blind=FALSE)

# now ploting
pdf("MLplots.pdf")
### 1: plotPCA with top 500, default
plotPCA(rld, intgroup=c("condition", "genome"))
data <- plotPCA(rld, intgroup=c("condition", "genome"), returnData=TRUE)
percentVar <- round(100 * attr(data, "percentVar"))
### 2. same as plotPCA with shape
ggplot(data, aes(PC1, PC2, color=condition, shape=genome)) +
geom_point(size=3) +
xlab(paste0("PC1: ",percentVar[1],"% variance")) +
ylab(paste0("PC2: ",percentVar[2],"% variance")) +
ggtitle("Top 500 genes - plotPCA default")
### 3. consider only flowing genes
data <- sumPCA(rld, genes= ftgenes, intgroup=c("condition", "genome"), ntop = length(ftgenes) )
percentVar <- round(100 * attr(data, "percentVar"))
ggplot(data=data, aes(PC1, PC2, color=condition, shape=genome)) +
geom_point(size=3) +
xlab(paste0("PC1: ",percentVar[1],"% variance")) +
ylab(paste0("PC2: ",percentVar[2],"% variance")) +
ggtitle("Flowering genes")
### 4. Heatmap of the count matrix for flower genes
library("pheatmap")
df <- as.data.frame(colData(dds)[,c("condition","type")])
pheatmap(assay(rld)[ftgenes,], cluster_rows=TRUE, show_rownames=FALSE,cluster_cols=TRUE, annotation_col=coldata[,c("condition","genome")], fontsize_row = 4, fontsize_col = 8)
###
dev.off()
###########   END

# Expression profiles of flowering genes are dominated by difference between sunrise(LD7 and SD7) and sunset(LD9 and SD5)


# pairwise deseq workflow
batch<- rbind(
c("A2.10", "A2.20" ),
c("A2.20", "A2.30" ),
c("A2.30", "A2.40" ),
c("A2.10", "A2.40" ),

c("D5.10", "D5.20" ),
c("D5.20", "D5.30" ),
c("D5.30", "D5.40" ),
c("D5.10", "D5.40" ),

c("AD3.10", "AD3.20" ),
c("AD3.20", "AD3.30" ),
c("AD3.30", "AD3.40" ),
c("AD3.10", "AD3.40" ),

c("TM1.10", "TM1.20" ),
c("TM1.20", "TM1.30" ),
c("TM1.30", "TM1.40" ),
c("TM1.10", "TM1.40" ),

c("Yuc.10", "Yuc.20" ),
c("Yuc.20", "Yuc.30" ),
c("Yuc.30", "Yuc.40" ),
c("Yuc.10", "Yuc.40" ) )

pairwiseDE<-function(dds, contrast,savePath)
{
    # DE analysis
    print(contrast)
    ddsPW <-dds[,dds$sample %in% contrast]
    ddsPW$sample<-droplevels(ddsPW$sample)
    res <- results(DESeq(ddsPW))
    print( summary(res,alpha=.05) ) # print results
    write.table(res, file=paste(savePath,"DE/",paste(contrast, collapse="vs"),".txt", sep=""), sep="\t")
}

apply(batch,1,function(x) pairwiseDE(dds,x,savePath = ""))

# deal with dpa change in syn genome
syn<-count[,c(1:5,7:12)] + count[,25:35]
syncol<-data.frame(genome="syn", dpa=rep(c(10,20,30,40),each=3), rep=1:3)
syncol<-syncol[c(1:5,7:12),]
syncol$sample<-paste(syncol$genome,syncol$dpa,sep="")
syncol<-syncol[,c("sample","genome","dpa","rep")]
rownames(syncol) <-paste(syncol$sample, syncol$rep,sep=".")
names(syn)<-rownames(syncol)
dds <- DESeqDataSetFromMatrix( countData = syn, colData = syncol, design = ~ sample)
batch<- rbind(
c("syn10", "syn20" ),
c("syn20", "syn30" ),
c("syn30", "syn40" ),
c("syn10", "syn40" ) )
apply(batch,1,function(x) pairwiseDE(dds,x,savePath = ""))

# multifactor design
fulldata<-cbind(count,syn)
fullcol<- rbind(coldata,syncol)
dds <- DESeqDataSetFromMatrix( countData = fulldata, colData = fullcol, design = ~ genome + dpa)
dds <- DESeq(dds)

batch <- rbind(
c("dpa","10","20"),
c("dpa","20","30"),
c("dpa","30","40"),
c("genome", "A2","D5"),
c("genome", "syn","Yuc"),
c("genome", "syn","TM1"),
c("genome", "syn","AD3"),
c("genome", "TM1","AD3"),
c("genome", "TM1","Yuc"),
c("genome", "AD3","Yuc")
)
apply(batch,1,function(x) { res <- results(dds, x); print(x); print( summary(res,alpha=.05) ); write.table(res, file=paste("DE/",paste(x[2:3], collapse="vs"),".txt", sep=""), sep="\t")})


# read in all files for summary
files<-grep("txt",list.files("DE"),value=TRUE)
for(each in files)
{
    x<-read.table(paste("DE/",each,sep=""), header=TRUE, row.names=1,sep="\t")
    x<- x[!is.na(x$padj) & x$padj<0.05,]
    print( paste(each,": up-",dim(x[x$log2FoldChange>0,])[1],", down-",dim(x[x$log2FoldChange<0,])[1], sep="") )
}
# "10vs20.txt: up-7649, down-8200"
# "20vs30.txt: up-8350, down-7983"
# "30vs40.txt: up-4317, down-5716"
# "A2.10vsA2.20.txt: up-4941, down-4407"
# "A2.10vsA2.40.txt: up-5795, down-4899"
# "A2.20vsA2.30.txt: up-3444, down-2866"
# "A2.30vsA2.40.txt: up-636, down-802"
# "A2vsD5.txt: up-8997, down-9597"
# "AD3.10vsAD3.20.txt: up-4886, down-4377"
# "AD3.10vsAD3.40.txt: up-7811, down-7971"
# "AD3.20vsAD3.30.txt: up-2507, down-2457"
# "AD3.30vsAD3.40.txt: up-1492, down-1974"
# "AD3vsYuc.txt: up-3506, down-3180"
# "D5.10vsD5.20.txt: up-4904, down-4767"
# "D5.10vsD5.40.txt: up-4188, down-3887"
# "D5.20vsD5.30.txt: up-4326, down-4056"
# "D5.30vsD5.40.txt: up-769, down-98"
# "syn10vssyn20.txt: up-5177, down-5243"
# "syn10vssyn40.txt: up-6276, down-5846"
# "syn20vssyn30.txt: up-4336, down-3728"
# "syn30vssyn40.txt: up-1007, down-404"
# "synvsAD3.txt: up-5177, down-6815"
# "synvsTM1.txt: up-5002, down-6446"
# "synvsYuc.txt: up-4703, down-5827"
# "TM1.10vsTM1.20.txt: up-3102, down-2208"
# "TM1.10vsTM1.40.txt: up-6152, down-5550"
# "TM1.20vsTM1.30.txt: up-4959, down-5148"
# "TM1.30vsTM1.40.txt: up-22, down-16"
# "TM1vsAD3.txt: up-4891, down-5286"
# "TM1vsYuc.txt: up-3345, down-3202"
# "Yuc.10vsYuc.20.txt: up-2846, down-1456"
# "Yuc.10vsYuc.40.txt: up-3929, down-3570"
# "Yuc.20vsYuc.30.txt: up-3369, down-3086"
# "Yuc.30vsYuc.40.txt: up-219, down-187"


dev<-list(A2=c("A2.10vsA2.20.txt","A2.20vsA2.30.txt","A2.30vsA2.40.txt"), D5=c("D5.10vsD5.20.txt","D5.20vsD5.30.txt","D5.30vsD5.40.txt"), syn=c("syn10vssyn20.txt","syn20vssyn30.txt","syn30vssyn40.txt"), AD3=c("AD3.10vsAD3.20.txt","AD3.20vsAD3.30.txt","AD3.30vsAD3.40.txt"), Yuc=c("Yuc.10vsYuc.20.txt","Yuc.20vsYuc.30.txt","Yuc.30vsYuc.40.txt"), TM1=c("TM1.10vsTM1.20.txt","TM1.20vsTM1.30.txt","TM1.30vsTM1.40.txt"))
id<-list()
for(i in 1:6)
{
    genome<-dev[[i]]
    y<-c()
    for(each in genome)
    {
         x<-read.table(paste("DE/",each,sep=""), header=TRUE, row.names=1,sep="\t")
         x<- x[!is.na(x$padj) & x$padj<0.05,]
         y<-unique(c(y,row.names(x)))
         
     }
    print(length(y))
    id[[names(dev[i])]]<-y
}
sapply(id,length)
#A2    D5   syn   AD3   Yuc   TM1
# 12906 14480 15084 13022  9357 12592
DEid_dev <-id


condition<-list(dpa_10vs20="10vs20.txt",
dpa_20vs30="20vs30.txt",
dpa_30vs40="30vs40.txt",
A2vsD5 ="A2vsD5.txt",
synvsYuc = "synvsYuc.txt",
synvsTM1 = "synvsTM1.txt",
synvsAD3 = "synvsAD3.txt",
TM1vsAD3 = "TM1vsAD3.txt",
TM1vsYuc = "TM1vsYuc.txt",
AD3vsYuc = "AD3vsYuc.txt" )
id<-list()
for(i in 1:10)
{
    genome<-condition[[i]]
    y<-c()
    for(each in genome)
    {
        x<-read.table(paste("DE/",each,sep=""), header=TRUE, row.names=1,sep="\t")
        x<- x[!is.na(x$padj) & x$padj<0.05,]
        y<-unique(c(y,row.names(x)))
        
    }
    print(length(y))
    id[[names(condition[i])]]<-y
}
sapply(id,length)
# dpa_10vs20      dpa_20vs30      dpa_30vs40   genome_A2vsD5 genome_synvsYuc
# 15849           16333            10033           18594            10530
# genome_synvsTM1 genome_synvsAD3 genome_TM1vsAD3 genome_TM1vsYuc genome_AD3vsYuc
# 11448            11992            10177            6547            6686
DEid_con <-id

save(DEid_dev, DEid_con, file="DEid.Rdata")