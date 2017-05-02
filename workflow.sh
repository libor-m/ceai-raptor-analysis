# https://lucene.apache.org/core/6_5_0/analyzers-common/index.html
# https://lucene.apache.org/core/6_5_0/
# http://stackoverflow.com/questions/6334692/how-to-use-a-lucene-analyzer-to-tokenize-a-string


export PATH=/usr/lib/jvm/java-8-openjdk-amd64/jre/bin:$PATH
sbt console <<EOF

import org.apache.lucene.analysis.en.EnglishAnalyzer
import org.apache.lucene.analysis.Analyzer
import org.apache.lucene.analysis.TokenStream
import org.apache.lucene.analysis.tokenattributes.CharTermAttribute

// read json
import scala.io.Source
import spray.json._
import DefaultJsonProtocol._

val interesting = Source.fromInputStream(getClass.getResourceAsStream("/interesting.txt")).mkString.parseJson.convertTo[List[String]]
val nonInteresting = Source.fromInputStream(getClass.getResourceAsStream("/noninteresting.txt")).mkString.parseJson.convertTo[List[String]]

val eanalyzer = new EnglishAnalyzer()

def tokens(s: String, analyzer: Analyzer) = {
    val stream  = analyzer.tokenStream(null, s);
    val term = stream.addAttribute(classOf[CharTermAttribute])

    stream.reset();
    stream.incrementToken()

    val res = Stream.continually(
       (stream.incrementToken, term.toString)
    ).takeWhile(_._1).map {
       t => t._2
    }.toList

    stream.close()

    res
}

// tokens(interesting(0), eanalyzer)

var i1 = interesting.map((s:String) => (1, tokens(s, eanalyzer)))
var i2 = nonInteresting.map((s:String) => (0, tokens(s, eanalyzer)))

import java.io.PrintWriter
val pw = new PrintWriter("tokenized.tsv")
for ((label, toks) <- i1) pw.print("%d\t%s\n".format(label, toks.mkString(";")))
for ((label, toks) <- i2) pw.print("%d\t%s\n".format(label, toks.mkString(";")))
pw.close


//
// speed up query testing
//
import org.apache.lucene.store.RAMDirectory
import org.apache.lucene.index.{IndexReader, IndexWriter, IndexWriterConfig, IndexOptions};
import org.apache.lucene.document.{Document, Field, FieldType}
import org.apache.lucene.queryparser.classic.QueryParser
import org.apache.lucene.search.IndexSearcher
import org.apache.lucene.index.DirectoryReader

def doc2idx(docs: List[String], ana: Analyzer) = {
  val ramDirectory = new RAMDirectory()
  val idxCfg = new IndexWriterConfig(ana)
  val indexWriter = new IndexWriter(ramDirectory, idxCfg)
  val ft = new FieldType()
  ft.setIndexOptions(IndexOptions.DOCS_AND_FREQS_AND_POSITIONS_AND_OFFSETS)
  ft.setStored(true)

  def idxAdd(s: String) {
    val doc = new Document()
    doc.add(new Field("text", s, ft))
    indexWriter.addDocument(doc)
  }

  docs.foreach(idxAdd)
  indexWriter.close()

  ramDirectory
}

val iidx = doc2idx(interesting, eanalyzer)
val niidx = doc2idx(nonInteresting, eanalyzer)

//
// search in indices
// it's easier to search in two indices than to retrieve the docs
// and test properties..

val srch = (new IndexSearcher(DirectoryReader.open(iidx)),
            new IndexSearcher(DirectoryReader.open(niidx)))
val queryParser = new QueryParser("text", eanalyzer);

def hits(q: String) = {
    val query = queryParser.parse(q)
    (srch._1.count(query),
     srch._2.count(query))
}

def score(q: String) = {
    val query = queryParser.parse(q)
    val cnts = (srch._1.count(query), srch._2.count(query))
    (cnts, (3000 - q.length) * ((1.0 * cnts._1) / (cnts._1 + cnts._2)))
}

// 99 % recall means 1199 / 100 == 11 misses, 1188 hits!
hits("gambl||(+monei +loan)")
hits("gambl||(+monei +loan)||(+sell +import)||(+sell +inform)||(+sell +paid)||(+sell +hand)||dealer||compound||(+arm +busi)||(+owner +befor)||(+owner +friend)||(+import +art)||(+trade +(creat || house))")
// = (1138,115)

hits("gambl||dealer||compound||sell||(+arm +busi)||(+owner +befor)||(+owner +friend)||(+import +art)||(+trade +(creat || house))")
// = (1159,150)

hits("gambl||dealer||compound||sell||(+arm +busi)||(+owner +befor)||(+owner +friend)||(+import +art)||(+trade +(creat || house))||(+greatli +bank)||(+loan +monei)||(+simultan +(beg||subsequ))||e.j||(+credit +volleyball)||(+webber +lot)||(+export +dec)||hock||wrangl")
//  = (1190,154)

// before total optimization
score("gambl||dealer||compound||sell||(+arm +busi)||(+owner +(friend||befor))||(+import +art)||(+trade +(creat||house))||(+greatli +bank)||(+loan +monei)||(+simultan +(beg||subsequ))||e.j||(+webber +lot)||(+export +dec)||hock||wrangl")
// res238: ((Int, Int), Double) = ((1188,154),2455.6721311475408)

score("gambl dealer compound sell (+arm +busi) (+owner +(friend befor)) (+import +art) (+trade +(creat house)) (+greatli +bank) (+loan +monei) (+simult* +(beg subsequ)) e.j (+webber +lot) (+export +dec) hock wrangl")
// res265: ((Int, Int), Double) = ((1188,154),2472.4918032786886)

score("gambl dealer compou* sell (+arm +busi) (+owner +(friend befor)) (+import +art) (+trade +(creat house)) (+greatli +bank) (+loan +monei) (+simult* +(beg subs*)) e.j (+webber +lot) (+expo* +dec) hock w*gl")
// res277: ((Int, Int), Double) = ((1188,154),2477.8032786885246)

// check with sbt run
// query length: 201
// recall 0.9908256880733946
// precistion 0.8852459016393442
// score 2477.8032786885246

//
// manual boosting
// - having some decent query to begin with
// - filter out hits, do tree again..
//

import org.apache.lucene.index.memory.MemoryIndex
import org.apache.lucene.search.Query
import java.io.PrintWriter

def matchText(text: String, query: String, analyzer: Analyzer): Boolean = {
  val qp = new QueryParser("text", analyzer);
  val pquery = qp.parse(query)
  val index = new MemoryIndex()
  index.addField("text", text, analyzer)
  val score = index.search(pquery)
  score > 0.0f
}

var qq = "gambl||dealer||compound||sell||(+arm +busi)||(+owner +befor)||(+owner +friend)||(+import +art)||(+trade +(creat || house))||(+tool +same)"

var i1 = interesting.map((s:String) => (1, matchText(s, qq, eanalyzer), tokens(s, eanalyzer)))
var i2 = nonInteresting.map((s:String) => (0, matchText(s, qq, eanalyzer), tokens(s, eanalyzer)))

val pw = new PrintWriter("tokenized-query.tsv")
for ((label, hit, toks) <- i1) pw.print("%d\t%b\t%s\n".format(label, hit, toks.mkString(";")))
for ((label, hit, toks) <- i2) pw.print("%d\t%b\t%s\n".format(label, hit, toks.mkString(";")))
pw.close

EOF


# bigml model
. bigml-auth.sh

MODEL=59078987014404467d00172e
curl "https://bigml.io/model/$MODEL?$BIGML_AUTH" > data/model-1click.json

#
flatline<<EOF
(if
  (and
    (= (field "field1") "1")
    (= (field "field2") "false"))
  "FN"
  "OK")

(if
  (and
    (= (field "field1") "0")
    (= (field "field2") "true"))
  "FP"
  "OK")

(if
  (= (field "field1") "0")
  (if
    (= (field "field2") "true")
    "FP"
    "TN")
  (if
    (= (field "field2") "false")
    "FN"
    "TP"))

EOF

queries<<EOF
# (1138,115)
gambl
dealer
compound
(+monei +loan)
(+sell +import)
(+sell +inform)
(+sell +paid)
(+sell +hand)
(+arm +busi)
(+owner +befor)
(+owner +friend)
(+import +art)
(+trade +(creat || house))

# (1176,152)
gambl
dealer
compound
sell
(+arm +busi)
(+owner +befor)
(+owner +friend)
(+import +art)
(+trade +(creat || house))
(+greatli +bank)
(+loan +monei)

# (1190,154)
# query length: 265
# recall 0.9924937447873228
# precistion 0.8854166666666666
# score 2421.614583333333

gambl
dealer
compound
sell
(+arm +busi)
(+owner +befor)
(+owner +friend)
(+import +art)
(+trade +(creat||house))
(+greatli +bank)
(+loan +monei)
(+simultan +(beg||subsequ))
e.j
(+credit +volleyball)
(+webber +lot)
(+export +dec)
hock
wrangl
EOF

# (3k - query len) * prec

