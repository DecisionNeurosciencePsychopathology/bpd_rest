compute_nodal_metrics <- function(allg_density, ncpus=4, allowCache=TRUE, community_attr="community", weighted = FALSE) {
  require(foreach)
  require(doSNOW)
  
  expectFile <- file.path(basedir, "cache", paste0("dthreshnodemetrics_", parcellation, "_", preproc_pipeline, "_", conn_method, ".RData"))
  if (file.exists(expectFile) && allowCache==TRUE) {
    message("Loading density-thresholded nodal statistics from file: ", expectFile)
    load(expectFile)
  } else {
    ###compute nodal metrics 
    setDefaultClusterOptions(master="localhost")
    clusterobj <- makeSOCKcluster(ncpus)
    registerDoSNOW(clusterobj)
    on.exit(try(stopCluster(clusterobj))) #shutdown cluster when function exits (either normally or crash)
    
    allmetrics.nodal <- foreach(subj=allg_density, .packages = c("igraph", "brainGraph"), .export=c("calcGraph_nodal", "gateway_coeff_NH", "wibw_module_degree", "densities_desired")) %dopar% {
      #for (subj in allg_density) { #put here for more fine-grained debugging
      if(weighted == FALSE){
      dl <- lapply(subj, function(dgraph) {
        glist <- calcGraph_nodal(dgraph, community_attr=community_attr)
        glist$id <- dgraph$id #copy attributes for flattening to data.frame
        glist$density <- dgraph$density
        glist$node <- V(dgraph)$name
        return(glist)
      }) } else {
        dl <- lapply(subj, function(dgraph) {
          glist <- calcGraph_nodal(dgraph, community_attr=community_attr, weighted = TRUE)
          glist$id <- dgraph$id #copy attributes for flattening to data.frame
          glist$density <- dgraph$density
          glist$node <- V(dgraph)$name
          return(glist)
        })
      }
      
      names(dl) <- paste0("d", densities_desired)
      
      return(dl)
    }
    
    #flatten metrics down to a data.frame (assumes that each vector in the list (dens below) is of the same length
    #this should hold in general because these are nodal statistics and node number is constant
    #allmetrics.nodal is currently a [[subjects]][[densities]][[metrics]] list
    allmetrics.nodal.df <- do.call(rbind, lapply(allmetrics.nodal, function(subj) {
      do.call(rbind, lapply(subj, function(dens) {
        as.data.frame(dens) #should just be a list
      }))
    }))
    
    row.names(allmetrics.nodal.df) <- NULL #remove goofy d0.01 rownames
    save(allmetrics.nodal, allmetrics.nodal.df, file = expectFile)
  }
  
  return(list(allmetrics.nodal=allmetrics.nodal, allmetrics.nodal.df=allmetrics.nodal.df))
}