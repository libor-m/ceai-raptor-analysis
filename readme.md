# raptor
CEAi MLPrague challenge

## code
In `workflow.sh`, a bit messy because it's just a recorded interactive session in `sbt console`.

## approach description

  - tokenize the documents
  - move to BigML, train a model (tree) on items
  - use the model to manually build a query
  - check Lucene query syntax thoroughly to make it as short as possible
  - empirically test if it's better to have shorter or more precise query
  - shorter gives better scores >> lower recall and precision as possible to get a short query

## result query
In `query.txt`, should score like this:

    query length: 201
    recall 0.9908256880733946
    precistion 0.8852459016393442
    score 2477.8032786885246



code, approach description and result query to mlprague@ceai.io with subject "Raptor task".