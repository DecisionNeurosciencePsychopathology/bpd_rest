setup_graphs <- function(adjmatarray, allowCache=TRUE, ncpus=4) {
  #expects a subjects x ROIs x ROIs array
  #creates igraph objects from adjacency matrix and label nodes V1, V2,...
  #looks up atlas from global environment
  suppressMessages(require(igraph))
  suppressMessages(require(foreach))
  suppressMessages(require(doSNOW))
  
  #### Setup basic weighted graphs
  expectFile <- file.path(basedir, "cache", paste0("weightedgraphs_", parcellation, "_", preproc_pipeline, "_", conn_method, ".RData"))
  if (file.exists(expectFile) && allowCache==TRUE) {
    message("Loading weighted graph objects from file: ", expectFile)
    load(expectFile)
  } else {
    allg <- apply(adjmatarray, 1, function(sub) {
      g <- graph.adjacency(sub, mode="undirected", weighted=TRUE, diag=FALSE)
      V(g)$name <- c(paste0("V", 1:248),paste0("V", 251:271))
      g <- tagGraph(g, atlas) #populate all attributes from atlas to vertices
      return(g)
    })
    
    #add id to graphs
    for (i in 1:length(allg)) { allg[[i]]$id <- dimnames(adjmatarray)[["id"]][i] }
    save(file=expectFile, allg) #save cache
  }
  
  #### Setup weighted graphs, removing negative edges
  expectFile <- file.path(basedir, "cache", paste0("weightedgraphsnoneg_", parcellation, "_", preproc_pipeline, "_", conn_method, ".RData"))
  if (file.exists(expectFile) && allowCache==TRUE) {
    message("Loading weighted non-negative graph objects from file: ", expectFile)
    load(expectFile)
  } else {
    ##remove negative correlations between nodes, if this is run on pearson, the number of edges remaining will be different across subjs 
    allg_noneg <- lapply(allg, function(g) { delete.edges(g, which(E(g)$weight < 0)) })
    save(file=expectFile, allg_noneg) #save cache
  }
  
  ### DENSITY THRESHOLDING: binarize and threshold graphs at densities ranging from 1-20%
  #uses densities_desired from setup_globals.R
  
  expectFile <- file.path(basedir, "cache", paste0("dthreshgraphs_", parcellation, "_", preproc_pipeline, "_", conn_method, ".RData"))
  if (file.exists(expectFile) && allowCache==TRUE) {
    message("Loading density-thresholded graph objects from file: ", expectFile)
    load(expectFile)
  } else {
    setDefaultClusterOptions(master="localhost")
    clusterobj <- makeSOCKcluster(ncpus)
    registerDoSNOW(clusterobj)
    
    #make sure .inorder = TRUE to keep subject sorting the same in a parallel loop
    allg_density <- foreach(g=allg_noneg, .packages=c("igraph", "tidyr"), .export=c("densities_desired", "density_threshold"), .inorder = TRUE) %dopar% {
      #nnodes <- length(V(g))
      #maxedges <- (nnodes*(nnodes-1))/2
      
      dgraphs <- lapply(densities_desired, density_threshold, g=g) #implicitly passes the dth element of densities_desired to density_threshold function      
      names(dgraphs) <- paste0("d", densities_desired)
      return(dgraphs)
    }
    
    names(allg_density) <- names(allg_noneg) #propagate IDs at names to density-thresholded list
    stopCluster(clusterobj)
    
    #each element of allg_density is a list of 20 binary graphs for that subject at 1-20% density
    save(file=expectFile, allg_density)
  }
  
  return(list(allg=allg, allg_noneg=allg_noneg, allg_density=allg_density))
}