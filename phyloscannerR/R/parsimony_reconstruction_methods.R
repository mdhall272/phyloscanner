#' @keywords internal
#' @export split.hosts.to.subgraphs

split.hosts.to.subgraphs<- function(tree, blacklist, mode, tip.regex, sankoff.k, sankoff.p, useff, count.reads, m.thresh = 0, host.master.list=NULL, verbose = F, no.progress.bars = F){
  
  if (verbose) cat("Getting tip read counts...\n")
  
  # If no multifurcation-collapsing occurred, the minimum branch length is taken to be zero
  
  if(count.reads){
    if(m.thresh == -1){
      if(min(tree$edge.length)!=0){
        warning("You specified --readCountsMatterOnZeroLengthBranches but there are no zero-length branches in this tree. Consider setting a multifurcation threshold.")
      }
      m.thresh <- 0
      
    }
    
    tip.read.counts <- sapply(tree$tip.label, function(x) read.count.from.label(x, tip.regex))
    tip.read.counts[is.na(tip.read.counts)] <- 1
    tip.read.counts[blacklist] <- 1
    terminal.bls <- sapply(1:length(tree$tip.label), function(x) get.edge.length(tree, x))
    # read counts are only relevant for branches of "zero" (less than m.thresh) length
    tip.read.counts[which(terminal.bls > m.thresh)] <- 1
  } else {
    tip.read.counts <- rep(1, length(tree$tip.label))
  }

  tip.labels <- tree$tip.label
  
  if (verbose) cat("Identifying tips with host...\n")
  
  # Find host IDs from each tip
  
  tip.hosts <- sapply(tip.labels, function(x) host.from.label(x, tip.regex))

  non.host.tips <- which(is.na(sapply(tree$tip.label, function(name) host.from.label(name, tip.regex))))
  tip.hosts[c(non.host.tips, blacklist)] <- "unassigned"
  
  if(!any(tip.hosts != "unassigned")){
    cat("No hosts identified amongst the tips of this tree. Skipping parsimony reconstruction.\n")
    return(list(tree=tree, r.subgraphs=NULL))
  }
  
  # Find the complete list of hosts present in this tree minus blacklisting
  
  if (verbose) cat("Finding list of hosts...\n")
  
  if(length(blacklist)>0){
    hosts <- unique(na.omit(tip.hosts[-blacklist]))
  } else {
    hosts <- unique(na.omit(tip.hosts))
  }
  
  hosts <- hosts[order(hosts)]
  
  if(!("unassigned" %in% hosts)){
    hosts <- c(hosts, "unassigned")
  }
  
  if(length(hosts)==0){
    cat("No host IDs detected after blacklisting for tree ",tree.file.name,", nothing to do.\n",sep="")
    return(list(tree=tree, rs.subgraphs=NULL))    
  } 
  
  # host.tips is a list of tips that belong to each host
  
  if (verbose) cat("Finding tips for each host...\n")
  
  host.tips <- lapply(hosts, function(x) which(tip.hosts==x))
  names(host.tips) <- hosts
  
  # host.mrcas is a list of MRCA nodes for each host
  
  if (verbose) cat("Finding MRCAs for each host...\n")
  
  host.mrcas <- lapply(host.tips, function(node) mrca.phylo.or.unique.tip(tree, node))
  
  # Do the main function

  results <- split.and.annotate(tree, 
                                hosts, 
                                tip.hosts, 
                                host.tips, 
                                host.mrcas, 
                                blacklist, 
                                tip.regex, 
                                mode, 
                                tip.read.counts, 
                                sankoff.k, 
                                sankoff.p, 
                                useff, 
                                verbose,
                                no.progress.bars)
  
  # Where to put the node shapes that display subgraph MRCAs
  
  first.nodes <- rep(FALSE, length(tree$tip.label) + tree$Nnode)
  first.nodes[unlist(results$first.nodes)] <- TRUE
  
  # For display purposes. "unassigned" nodes should have NA as annotations
  
  split.annotation <- rep(NA, length(tree$tip.label) + tree$Nnode)
  
  for(item in seq(1, length(results$assocs))){
    if(!is.null(results$assocs[[item]])){
      if(!(results$assocs[[item]] %in% c("*", "unassigned", "unassigned.rt", "unassigned.int"))) {
        split.annotation[item] <- results$assocs[[item]]
      }
    }
  }

  # This is the annotation for each node by host
  
  host.annotation <- sapply(split.annotation, function(x) unlist(strsplit(x, "-SPLIT"))[1] )
  names(host.annotation) <- NULL
  
  if(is.null(host.master.list)){
    host.annotation <- factor(host.annotation, levels = sample(levels(as.factor(host.annotation))))
  } else {
    host.annotation <- factor(host.annotation, levels = host.master.list)
  }
  
  branch.colours <- host.annotation
  branch.colours[first.nodes] <- NA
  
  # For annotation
  # We will return the original tree with the original branch lengths
  
  attr(tree, 'SPLIT') <- factor(split.annotation)
  attr(tree, 'INDIVIDUAL') <- host.annotation
  attr(tree, 'BRANCH_COLOURS') <- branch.colours
  attr(tree, 'SUBGRAPH_MRCA') <- first.nodes
  
  rs.subgraphs <- data.table(subgraph=results$split.hosts)
  rs.subgraphs <- rs.subgraphs[, list(host= unlist(strsplit(subgraph, "-SPLIT"))[1], tip= tree$tip.label[ results$split.tips[[subgraph]] ]	), by='subgraph']
  rs.subgraphs <- as.data.frame(subset(rs.subgraphs, select=c(host, subgraph, tip)))
  
  list(tree=tree, rs.subgraphs=rs.subgraphs)
}

split.and.annotate <- function(tree, patients, tip.patients, patient.tips, patient.mrcas, blacklist, tip.regex, method="r", tip.read.counts, k=NA, p = 0, useff=F, verbose=F, no.progress.bars = F){
  
  if (method == "r") {
    
    if (verbose) cat("Applying the Romero-Severson parsimony classification to internal nodes...\n")
    
    tip.assocs <- annotate.tips(tree, patients, patient.tips)
    
    for(tip in seq(1, length(tree$tip.label))){
      if(tip %in% blacklist | is.na(host.from.label(tree$tip.label[tip], tip.regex))){
        tip.assocs[[tip]] <- "*"
      }
    }
    
    new.assocs <- classify.down(getRoot(tree), tree, tip.assocs, list(), patient.mrcas)
    
    if (verbose) cat("Filling in stars...\n")
    
    star.runs <- get.star.runs(tree, new.assocs)
    
    star.bottoms <- which(lengths(star.runs)>0)
    
    resolved.assocs <- new.assocs
    
    for(bottom in star.bottoms){
      child.assocs <- unlist(new.assocs[Children(tree, bottom)])
      c.a.df <- as.data.frame(table(child.assocs), stringsAsFactors=F)
      c.a.df <- c.a.df[which(c.a.df[,1]!="*"),]
      winners <- c.a.df[which(c.a.df[,2]==max(c.a.df[,2])),]
      possibilities <- winners[,1]
      
      last.in.chain <- star.runs[[bottom]][length(star.runs[[bottom]])]
      parent.lic <- Ancestors(tree, last.in.chain, type="parent")
      if(parent.lic!=0){
        parental.assoc <- new.assocs[[parent.lic]]
        if(parental.assoc %in% possibilities){
          
          resolved.assocs[star.runs[[bottom]]] <- parental.assoc
        } 
      }
    }
    
    # Now the splits. A new split is where you encounter a node with a different association to its parent
    
    if (verbose) cat("Identifying split hosts...\n")
    
    splits.count <- rep(0, length(patients))
    first.nodes <- list()
    
    splits <- count.splits(tree, getRoot(tree), resolved.assocs, patients, splits.count, first.nodes)
    
    counts.by.patient <- splits$counts
    first.nodes.by.patients <- splits$first.nodes
    
    patients.copy <- patients
    patient.tips.copy <- patient.tips
    
    split.assocs <- resolved.assocs
    
    #find the splits and reannotate the tree
    
    for(pat.no in seq(1, length(patients))){
      patient <- patients[pat.no]
      no.splits <- counts.by.patient[pat.no]
      
      if(no.splits>1){
        pat.tips <- patient.tips[[patient]]
        patient.tips.copy[[patient]] <- NULL
        patients.copy <- patients.copy[which(patients.copy!=patient)]
        patients.copy <- c(patients.copy, paste(patient,"-SPLIT",seq(1, no.splits),sep=""))
        
        for(tip in pat.tips){
          # go up until you find one of the first nodes
          current.node <- tip
          subtree.roots <- first.nodes.by.patients[[patient]]
          while(!(current.node %in% subtree.roots)){
            if(current.node == 0){
              stop("Reached the root?!")
            }
            current.node <- Ancestors(tree, current.node, type="parent")
          }
          split.index <- which(subtree.roots == current.node)
          new.name <- paste(patient,"-SPLIT", split.index, sep="")
          
          current.node <- tip
          split.assocs[[subtree.roots[split.index]]] <- new.name
          
          while(current.node != subtree.roots[split.index]){
            if(current.node == 0){
              stop("Reached the root?!")
            }
            split.assocs[[current.node]] <- new.name
            current.node <- Ancestors(tree, current.node, type="parent")
          }
          
          
          patient.tips.copy[[new.name]] <- c(patient.tips.copy[[new.name]], tip)
        }
      }
    }
    
    # No need for the stars anymore
    
    return(list(assocs = split.assocs, split.hosts = patients.copy, split.tips = patient.tips.copy, 
                first.nodes = first.nodes.by.patients))
    
    
  } else if (method=="s") {
    
    if(is.na(k)){
      stop("k must be specified for Sankoff reconstruction")
    }
    
    if (verbose) cat("Reconstructing internal node hosts with the Sankoff algorithm...\n")

    if (verbose) cat("Calculating node costs...\n")
    
    # This matrix is the cost of an infection for a given patient along the branch ENDING in a given
    # node. This is the distance from the START of the branch (could make it halfway at a later point) 
    # to the first tip from that patient
    
    if(useff){
      individual.costs <- ff(Inf, dim=c(length(tree$tip.label) + tree$Nnode,length(patients))) 
    } else {
      individual.costs <- matrix(Inf, ncol=length(patients), nrow=length(tree$tip.label) + tree$Nnode) 
    }
    
    # First, go up the tree and flag which nodes have finite costs for which patients (i.e. those
    # that are ancestral to a tip _from_ that patient)
    
    if(useff){
      finite.cost <- ff(FALSE, dim=c(length(tree$tip.label) + tree$Nnode, length(patients)))
    } else {
      finite.cost <- matrix(FALSE, ncol=length(patients), nrow=length(tree$tip.label) + tree$Nnode) 
    }
    
    for(tip in seq(1, length(tree$tip.label))){
      pat <- tip.patients[tip]
      finite.cost[tip, which(patients==pat)] <- TRUE
      current.node <- tip
      repeat{
        current.node <- Ancestors(tree, current.node, type="parent")
        
        if(finite.cost[current.node, which(patients==pat)]){
          # already been here
          break
        }
        finite.cost[current.node, which(patients==pat)] <- TRUE
        if(is.root(tree, current.node)){
          break
        }
      }
    }
    
    
    num.fc <- 1*!finite.cost

    # Then traverse
    

    for(pat.no in 1:length(patients)){
      start.col <- sapply(finite.cost[,pat.no], function(x) if(x) 0 else Inf)
      
      individual.costs[,pat.no] <- cost.of.subtree(tree, getRoot(tree), patients[pat.no], tip.patients, finite.cost[,pat.no], start.col)
    }
  
    # The rows of the cost matrix are nodes. The columns are patients; the last column is the unassigned
    # state
    
    if (verbose) cat("Building full cost matrix...\n")
    
    if(useff){
      cost.matrix <- ff(NA, dim=c(length(tree$tip.label) + tree$Nnode, length(patients)), vmode = "single")
    } else {
      cost.matrix <- matrix(NA, nrow=length(tree$tip.label) + tree$Nnode, ncol=length(patients))
    }
    
    progress.bar <- NULL
    
    if(verbose & !no.progress.bars) progress.bar <- txtProgressBar(width=50, style=3) else progress.bar <- NULL

    cost.matrix <- make.cost.matrix(getRoot(tree), tree, patients, tip.patients, individual.costs, cost.matrix, k, tip.read.counts, progress.bar, verbose)
    
    if(verbose & !no.progress.bars) close(progress.bar)
    
    if (verbose) cat("Reconstructing...\n")
    
    full.assocs <- reconstruct(tree, getRoot(tree), "unassigned", list(), tip.patients, patients, cost.matrix, individual.costs, k, p, tip.read.counts, verbose)
    
    temp.ca <- rep(NA, length(tree$tip.label) + tree$Nnode)
    
    for(item in seq(1, length(full.assocs))){
      if(!is.null(full.assocs[[item]])){
        if(full.assocs[[item]] != "unassigned"){
          temp.ca[item] <- full.assocs[[item]]
        }
      }
    }
    
    # Now the splits. A new split is where you encounter a node with a different association to its parent
    
    actual.patients <- patients[which(patients!="unassigned")]
    
    if (verbose) cat("Identifying split hosts...\n")
    
    splits.count <- rep(0, length(actual.patients))
    first.nodes <- list()
    
    splits <- count.splits(tree, getRoot(tree), full.assocs, actual.patients, splits.count, first.nodes)
    
    counts.by.patient <- splits$counts
    first.nodes.by.patients <- splits$first.nodes
    
    patients.copy <- actual.patients
    patient.tips.copy <- patient.tips
    
    split.assocs <- full.assocs
    
    #find the splits and reannotate the tree
    
    for(pat.no in seq(1, length(actual.patients))){
      patient <- actual.patients[pat.no]
      no.splits <- counts.by.patient[pat.no]
      
      if(no.splits>1){
        
        patient.tips.copy[[patient]] <- NULL
        patients.copy <- patients.copy[which(patients.copy!=patient)]
        patients.copy <- c(patients.copy, paste(patient,"-SPLIT",seq(1, no.splits),sep=""))
        
        subtree.roots <- first.nodes.by.patients[[patient]]
        
        for(split.no in 1:no.splits){
          split.root <- subtree.roots[split.no]
          new.name <- paste(patient,"-SPLIT", split.no, sep="")
          split.assocs[[split.root]] <- new.name
          split.assocs <- assign.splits.down(split.root, tree, full.assocs, split.assocs)
          
          for(tip in 1:length(tree$tip.label)){
            if(split.assocs[[tip]] == new.name){
              patient.tips.copy[[new.name]] <- c(patient.tips.copy[[new.name]], tip)
            }
          }
        }
      }
    }
    
    return(list(assocs = split.assocs, split.hosts = patients.copy, split.tips = patient.tips.copy, 
                first.nodes = first.nodes.by.patients))
    
  } else if(method=="f"){
    
    if(is.na(k)){
      stop("k must be specified for Sankoff reconstruction")
    }
    
    if (verbose) cat("Reconstructing internal node hosts with the Sankoff algorithm (continuation costs version)...\n")
    
    if (verbose) cat("Calculating node costs...\n")

    if(useff){
      finite.cost <- ff(TRUE, dim=c(length(tree$tip.label) + tree$Nnode, length(patients)))
    } else {
      finite.cost <- matrix(TRUE, ncol=length(patients), nrow=length(tree$tip.label) + tree$Nnode) 
    }
    
    # for(tip in seq(1, length(tree$tip.label))){
    #   pat <- tip.patients[tip]
    #   
    #   finite.cost[tip, which(patients==pat)] <- TRUE
    #   current.node <- tip
    #   repeat{
    #     current.node <- Ancestors(tree, current.node, type="parent")
    #     
    #     if(finite.cost[current.node, which(patients==pat)]){
    #       # already been here
    #       break
    #     }
    #     finite.cost[current.node, which(patients==pat)] <- TRUE
    #     if(is.root(tree, current.node)){
    #       break
    #     }
    #   }
    # }
    # 
    finite.cost[,which(patients=="unassigned")] <- TRUE
    
    if (verbose) cat("Building full cost matrix...\n")
    
    if(useff){
      cost.matrix <- ff(NA, dim=c(length(tree$tip.label) + tree$Nnode, length(patients)), vmode = "single")
    } else {
      cost.matrix <- matrix(NA, nrow=length(tree$tip.label) + tree$Nnode, ncol=length(patients))
    }
    
    if(verbose) progress.bar <- txtProgressBar(width=50, style=3)
    
    cost.matrix <- make.cost.matrix.fi(getRoot(tree), tree, patients, tip.patients, cost.matrix, k, p, finite.cost, tip.read.counts, progress.bar, verbose)
    
    close(progress.bar)
    
    if (verbose) cat("Reconstructing...\n")
  
    full.assocs <- reconstruct.fi(tree, getRoot(tree), "unassigned", list(), tip.patients, patients, cost.matrix, finite.cost, k, p, tip.read.counts, verbose)

    temp.ca <- rep(NA, length(tree$tip.label) + tree$Nnode)
    
    for(item in seq(1, length(full.assocs))){
      if(!is.null(full.assocs[[item]])){
        if(!(full.assocs[[item]] %in% c("unassigned.int", "unassigned.rt", "unassigned"))){
          temp.ca[item] <- full.assocs[[item]]
        }
      }
    }
    
    # Now the splits. A new split is where you encounter a node with a different association to its parent
    
    actual.patients <- patients[which(!(patients %in% c("unassigned")))]
    
    if (verbose) cat("Identifying split hosts...\n")
    
    splits.count <- rep(0, length(actual.patients))
    first.nodes <- list()
    
    splits <- count.splits(tree, getRoot(tree), full.assocs, actual.patients, splits.count, first.nodes)
    
    counts.by.patient <- splits$counts
    first.nodes.by.patients <- splits$first.nodes
    
    patients.copy <- actual.patients
    patient.tips.copy <- patient.tips
    
    split.assocs <- full.assocs
    
    #find the splits and reannotate the tree
    
    for(pat.no in seq(1, length(actual.patients))){
      patient <- actual.patients[pat.no]
      no.splits <- counts.by.patient[pat.no]
      
      if(no.splits>1){
        
        patient.tips.copy[[patient]] <- NULL
        patients.copy <- patients.copy[which(patients.copy!=patient)]
        patients.copy <- c(patients.copy, paste(patient,"-SPLIT",seq(1, no.splits),sep=""))
        
        subtree.roots <- first.nodes.by.patients[[patient]]
        
        for(split.no in 1:no.splits){
          split.root <- subtree.roots[split.no]
          new.name <- paste(patient,"-SPLIT", split.no, sep="")
          split.assocs[[split.root]] <- new.name
          split.assocs <- assign.splits.down(split.root, tree, full.assocs, split.assocs)
          
          for(tip in 1:length(tree$tip.label)){
            if(split.assocs[[tip]] == new.name){
              patient.tips.copy[[new.name]] <- c(patient.tips.copy[[new.name]], tip)
            }
          }
        }
      }
    }
    
    return(list(assocs = split.assocs, split.hosts = patients.copy, split.tips = patient.tips.copy, 
                first.nodes = first.nodes.by.patients))
    
  } else {
    stop("Unsupported splitting method")
  }
}

# ROMERO-SEVERSON METHODS

# Annotate just the tips with their patients

annotate.tips <- function(tree, patients, patient.tips){
  node.assocs <- list()
  for(patient in patients){
    for(tip in patient.tips[[patient]]){
      node.assocs[[tip]] <- patient
    }
  }
  return(node.assocs)
}

# Used to find every connected subtree in the whole tree by finding the earliest node in them

#' @keywords internal
#' @export count.splits

count.splits <- function(tree, node, assocs, patients, counts.vec, first.nodes.list){
  
  for(child in Children(tree, node)){
    child.results <- count.splits(tree, child, assocs, patients, counts.vec, first.nodes.list) 
    
    counts.vec <- child.results$counts
    first.nodes.list <- child.results$first.nodes
  }
  
  parent <- Ancestors(tree, node, type="parent")
  change <- F
  if(parent == 0){
    change <- T
  } else if (assocs[[parent]]!=assocs[[node]]){
    change <- T
  }
  
  if(!(assocs[[node]] %in% c("*", "unassigned", "unassigned.rt", "unassigned.int"))){
    if(change){
      patient <- assocs[[node]]
      pat.index <- which(patients == patient)
      counts.vec[pat.index] <- counts.vec[pat.index] + 1
      first.nodes.list[[patient]] <- c(first.nodes.list[[patient]], node)
    }
  }
  return(list(counts = counts.vec, first.nodes = first.nodes.list))
}

# Takes splits and annotates the tree with them

#' @keywords internal
#' @export assign.splits.down

assign.splits.down <- function(node, tree, unsplit.assocs, split.assocs){
  for(child in Children(tree, node)){
    if(unsplit.assocs[[child]] == unsplit.assocs[[node]]){
      split.assocs[[child]] <- split.assocs[[node]]
      split.assocs <- assign.splits.down(child, tree, unsplit.assocs, split.assocs)
    }
  }
  return(split.assocs)
}

# Does the RS classification

#' @keywords internal
#' @export classify.down

classify.down <- function(node, tree, tip.assocs, temp.assocs, patient.mrcas){
  
  current.assocs <- temp.assocs
  
  if(is.tip(tree, node)){
    result <- tip.assocs[[node]]
  } else {
    child.assocs.vector <- rep(NA, length(Children(tree, node)))
    
    for(i in seq(1,length(Children(tree, node)))){
      child <- Children(tree, node)[i]
      new.assocs <- classify.down(child, tree, tip.assocs, current.assocs, patient.mrcas)
      child.assocs.vector[i] <- new.assocs[[child]]
      current.assocs <- new.assocs
    }
    
    c.a.df <- as.data.frame(table(child.assocs.vector), stringsAsFactors=F )
    
    if(nrow(c.a.df)==1){
      result <- c.a.df[1,1]
    } else {
      c.a.df <- c.a.df[which(c.a.df[,1]!="*"),]
      
      winners <- c.a.df[which(c.a.df[,2]==max(c.a.df[,2])),]
      if(nrow(winners)==1){
        result <- winners[1,1]
      } else {
        result <- "*"
      }
    }
  }
  
  #check that this isn't above the MRCA for the patient, which leads to weird results
  
  if(result != "*"){
    if(node %in% Ancestors(tree, patient.mrcas[[result]], type="all")){
      result <- "*"
    }
  }
  
  current.assocs[[node]] <- result
  return(current.assocs)
}

# "Star runs" are sequences of ancestors that are assigned "*" by the RS classification. Once the
# classification is done, they can be converted to having assigned nodes if the ancestor of the
# earliest node is a possible host for all nodes in the run

#' @keywords internal
#' @export get.star.runs

get.star.runs <- function(tree, assocs){
  out <- list()
  for(int.node in seq(length(tree$tip.label) + 1,  length(tree$tip.label) + tree$Nnode)){
    if(assocs[[int.node]]=="*"){
      #need to check that it got the star because of an ambiguity, not because there are only stars around there
      child.assocs <- unlist(assocs[Children(tree, int.node)])
      c.a.df <- as.data.frame(table(child.assocs), stringsAsFactors=F)
      c.a.df <- c.a.df[which(c.a.df[,1]!="*"),]
      if(nrow(c.a.df)>1){
        run <- int.node
        current.node <- Ancestors(tree, int.node, type="parent")
        if(current.node != 0){
          while(assocs[[current.node]]=="*"){
            run <- c(run, current.node)
            current.node <- Ancestors(tree, current.node, type="parent")
            if(current.node == 0){
              break
            }
          }
        }
        out[[int.node]] <- run
      }
    }
  }
  return(out)
}

# SANKOFF METHODS

# Make the full Sankoff cost matrix

#' @keywords internal
#' @export make.cost.matrix

make.cost.matrix <- function(node, tree, patients, tip.patients, individual.costs, current.matrix, k, tip.read.counts, progress.bar=NULL, verbose = F){
  # if(verbose){
  #   cat("Node number ",node,":", sep="")
  # }
  if(is.tip(tree, node)){
    # if(verbose){
    #   cat(" is a tip (host = ",tip.patients[node],")\n", sep="")
    # }
    current.matrix[node,] <- rep(Inf, length(patients))
    current.matrix[node, which(patients == tip.patients[node])] <- 0
    
  } else {
    # if(verbose){
    #   cat(" looking at children (")
    #   cat(Children(tree, node),sep=" ")
    #   cat(")\n")
    # }
    this.row <- vector()
    child.nos <- Children(tree, node)
    for(child in child.nos){
      current.matrix <- make.cost.matrix(child, tree, patients, tip.patients, individual.costs, current.matrix, k, tip.read.counts, progress.bar, verbose)
    }
    if(length(child.nos)==0){
      stop("Reached an internal node with no children(?)")
    }
    # if(verbose){
    #   cat("Done; back to node ",node,"\n", sep="")
    # }
    current.matrix[node,] <- vapply(seq(1, length(patients)), function(x) node.cost(tree, x, patients, current.matrix, individual.costs, k, child.nos, tip.read.counts), 0)
    
    # if(verbose){
    #   cat("Row for node ",node," calculated\n", sep="")
    # }
    
  }
  # if(verbose){
  #   ties.string <- format(patients[which(current.matrix[node,] == min(current.matrix[node,]))],sep=" ")
  #   cat("Lowest cost (",min(current.matrix[node,]),") for node ",node," goes to ",sep="")
  #   cat(ties.string, "\n")
  #   cat("\n")  
  # }
  
  if(verbose & !is.null(progress.bar)){
    setTxtProgressBar(progress.bar, length(which(!is.na(current.matrix[,1])))/nrow(current.matrix))
  }
  
  return(current.matrix)
}

#' @keywords internal
#' @export node.cost

node.cost <- function(tree, patient.index, patients, current.matrix, individual.costs, k, child.nos, tip.read.counts){
  return(sum(vapply(child.nos, function (x) child.min.cost(tree, x, patients, patient.index, current.matrix, individual.costs, k, tip.read.counts), 0)))
}

#' @keywords internal
#' @export child.min.cost

child.min.cost <- function(tree, child.index, patients, top.patient.no, current.matrix, individual.costs, k, tip.read.counts){
  if(is.tip(tree, child.index)){
    multiplier <- tip.read.counts[child.index]
  } else {
    multiplier <- 1
  }

  scores <- rep(Inf, length(patients))
  
  finite.scores <- unique(c(top.patient.no, which(patients=="unassigned"), which(is.finite(individual.costs[child.index,]))))
  finite.scores <- finite.scores[order(finite.scores)]
  
  scores[finite.scores] <- vapply(finite.scores, function(x) child.cost(tree, child.index, patients, top.patient.no, x, current.matrix, individual.costs, k, multiplier), 0)
  
  return(min(scores))
}

# Submethods of the above

#' @keywords internal
#' @export child.cost

child.cost <- function(tree, child.index, patients, top.patient.no, bottom.patient.no, current.matrix, individual.costs, k, multiplier=1){
  if(top.patient.no == bottom.patient.no) {
    out <- current.matrix[child.index, bottom.patient.no]
  } else if (patients[bottom.patient.no] != "unassigned") {
    out <- current.matrix[child.index, bottom.patient.no] + multiplier + k*individual.costs[child.index, bottom.patient.no]
    if(is.nan(out)) {
      out <- Inf
    }
  } else {
    # No cost for transition to unassigned
    out <- current.matrix[child.index, bottom.patient.no]
  }
  return(out)
}

# Reconstruct node states based on the cost matrix. 

#' @keywords internal
#' @export reconstruct

reconstruct <- function(tree, node, node.state, node.assocs, tip.patients, patients, full.cost.matrix, node.cost.matrix, k, p, tip.read.counts, verbose=F){
  node.assocs[[node]] <- node.state
  # if(verbose){
  #   cat("Node ",node," reconstructed as ",node.state,"\n", sep="")
  # }
  if(is.tip(tree, node)){
    if(node.state != tip.patients[node]){
      stop("Attempting to reconstruct the wrong state onto a tip")
    }
    decision <- node.state
  } else {
    for(child in Children(tree, node)){
      if(is.tip(tree, child)){
        multiplier <- tip.read.counts[child]
      } else {
        multiplier <- 1
      }
      
      
      costs <- vapply(seq(1, length(patients)), function(x) calc.costs(x, patients, node.state, child, node.cost.matrix, full.cost.matrix, k, multiplier), 0)
      
      min.cost <- min(costs)
      if(length(which(costs == min.cost))==1){
        decision <- patients[which(costs == min.cost)]
        # if(verbose){
        #   cat("Single minimum cost belongs to ", decision, "\n", sep="")
        # }
      } else {
        # if(verbose){
        #   cat("Tie at node ",node," between ",cat(patients[which(costs == min.cost)], sep=" "),"...", sep="")
        # }
        if("unassigned" %in% patients[which(costs == min.cost)] & node.state %in% patients[which(costs == min.cost)]){
          child.branch.length <- get.edge.length(tree, child)
          if(child.branch.length > p){
            # if(verbose){
            #   cat("broken in favour of unassigned\n")
            # }
            decision <- "unassigned"
          } else {
            # if(verbose){
            #   cat("broken in favour of",node.state,"\n")
            # }
            decision <- node.state
          }
        } else {
          decision <- patients[sample(which(costs == min.cost), 1)]
          # if(verbose){
          #   cat("broken in favour of", decision, '\n')
          # }
          cat("WARNING: some ties broken at random\n", sep="")
        }
      }
      node.assocs <- reconstruct(tree, child, decision, node.assocs, tip.patients, patients, full.cost.matrix, node.cost.matrix, k, p, tip.read.counts, verbose)
    }
  }
  return(node.assocs)
}

# Submethods of the above

#' @keywords internal
#' @export calc.costs

calc.costs <- function(patient.no, patients, node.state, child.node, node.cost.matrix, full.cost.matrix, k, multiplier=1){
  patient <- patients[patient.no]
  
  if(patient == node.state){
    # No cost for the transition because it doesn't happen here
    out <- full.cost.matrix[child.node, patient.no]
  } else if(patient == "unassigned"){
    # "unassigned" - no cost for the infection
    out <- full.cost.matrix[child.node, patient.no]
  } else {
    # the cost of "patient" being at the child plus the cost of "patient" being infected along this branch 
    out <- full.cost.matrix[child.node, patient.no] + multiplier + k*node.cost.matrix[child.node, patient.no]
    if(is.nan(out)){
      out <- Inf
    }
  }
  return(out)
}

#' @keywords internal
#' @export cost.of.subtree

cost.of.subtree <- function(tree, node, patient, tip.patients, finite.cost.col, results, progress.bar = NULL){
  if(is.tip(tree, node)){
    if(patient == tip.patients[node]){
      results[node] <- 0
    } else {
      stop("A tip with the wrong association has been reached")
    }
  } else {
    for(child in Children(tree, node)){
      if(finite.cost.col[child]){
        results <- cost.of.subtree(tree, child, patient, tip.patients, finite.cost.col, results, progress.bar)
        results[node] <- results[node] + results[child] + get.edge.length(tree, child)
      }
    }
  }
  return(results)
}


# Reconstruct node states based on the cost matrix. 

#' @keywords internal
#' @export make.cost.matrix.fi

make.cost.matrix.fi <- function(node, tree, patients, tip.assocs, current.matrix, k, us.penalty, finite.costs, tip.read.counts, progress.bar = NULL, verbose = F){
  # if(verbose){
  #   cat("Node number ",node,":", sep="")
  # }
  if(is.tip(tree, node)){
    # if(verbose){
    #   cat(" is a tip (host = ",tip.assocs[[node]],")\n", sep="")
    # }
    current.matrix[node,] <- rep(Inf, length(patients))
    current.matrix[node, which(patients == tip.assocs[[node]])] <- 0
    
  } else {
    # if(verbose){
    #   cat(" looking at children (")
    #   cat(Children(tree, node),sep=" ")
    #   cat(")\n")
    # }
    this.row <- vector()
    child.nos <- Children(tree, node)
    for(child in child.nos){

      current.matrix <- make.cost.matrix.fi(child, tree, patients, tip.assocs, current.matrix, k, us.penalty, finite.costs, tip.read.counts, progress.bar, verbose)
    }
    if(length(child.nos)==0){
      stop("Reached an internal node with no children(?)")
    }
    # if(verbose){
    #   cat("Done; back to node ",node,"\n", sep="")
    # }
    current.matrix[node,] <- vapply(seq(1, length(patients)), function(x) node.cost.fi(tree, child.nos, x, patients, current.matrix, k, us.penalty, finite.costs, tip.read.counts), 0)
    
    # if(verbose){
    #   cat("Row for node ",node," calculated\n", sep="")
    # }
    
  }
  # if(verbose){
  #   ties.string <- format(patients[which(current.matrix[node,] == min(current.matrix[node,]))],sep=" ")
  #   cat("Lowest cost (",min(current.matrix[node,]),") for node ",node," goes to ",sep="")
  #   cat(ties.string, "\n")
  #   cat("\n")  
  # }
  if(verbose & !is.null(progress.bar)){

    setTxtProgressBar(progress.bar, length(which(!is.na(current.matrix[,1])))/nrow(current.matrix))
  }
  
  return(current.matrix)
}

#' @keywords internal
#' @export node.cost.fi

node.cost.fi <- function(tree, child.nos, patient.index, patients, current.matrix, k, us.penalty, finite.costs, tip.read.counts){
  return(sum(vapply(child.nos, function (x) child.min.cost.fi(tree, x, patient.index, patients, current.matrix, k, us.penalty, finite.costs, tip.read.counts), 0)))
}

#' @keywords internal
#' @export child.min.cost.fi

child.min.cost.fi <- function(tree, child.index, top.patient.no, patients, current.matrix, k, us.penalty, finite.costs, tip.read.counts){

  if(is.tip(tree, child.index)){
    multiplier <- tip.read.counts[child.index]
  } else {
    multiplier <- 1
  }
  
  scores <- rep(Inf, length(patients))
  
  finite.scores <- unique(c(top.patient.no, which(patients=="unassigned"), which(finite.costs[child.index,])))

  finite.scores <- finite.scores[order(finite.scores)]
  
  scores[finite.scores] <- vapply(finite.scores, function(x) child.cost.fi(tree, child.index, patients, top.patient.no, x, current.matrix, k, us.penalty, multiplier), 0)
  
  return(min(scores))
}

# Submethods of the above

#' @keywords internal
#' @export child.cost.fi

child.cost.fi <- function(tree, child.index, patients, top.patient.no, bottom.patient.no, current.matrix, k, us.penalty, multiplier = 1){
  bl <- get.edge.length(tree, child.index)
  out <- current.matrix[child.index, bottom.patient.no]
  if(patients[top.patient.no] == "unassigned"){
    if(patients[bottom.patient.no] == "unassigned"){
      out <- out + us.penalty
    } else {
      out <- out + ((1/k)-us.penalty)*multiplier
    }
  } else {
    if(patients[bottom.patient.no] == "unassigned"){
      out <- out + us.penalty
    } else if(top.patient.no == bottom.patient.no){
      out <- out + bl
    } else {
      out <- out + ((1/k)-us.penalty)*multiplier
    }
  }
  return(out)
}

#' @keywords internal
#' @export reconstruct.fi

reconstruct.fi <- function(tree, node, node.state, node.assocs, tip.assocs, patients, full.cost.matrix, finite.costs, k, penalty, tip.read.counts, verbose=F){
  node.assocs[[node]] <- node.state
  # if(verbose){
  #   cat("Node ",node," reconstructed as ",node.state,"\n", sep="")
  # }
  if(is.tip(tree, node)){
    if(node.state != tip.assocs[[node]]){
      stop("Attempting to reconstruct the wrong state onto a tip")
    }
    decision <- node.state
  } else {
    for(child in Children(tree, node)){
      if(is.tip(tree, child)){
        multiplier <- tip.read.counts[child]
      } else {
        multiplier <- 1
      }
      
      bl <- get.edge.length(tree, child)
      costs <- rep(Inf, length(patients))
      costs.that.are.finite <- unique(c(which(patients=="unassigned"), which(patients==node.state), which(finite.costs[child,])))
      costs[costs.that.are.finite] <- vapply(costs.that.are.finite, function(x) calc.costs.fi(x, patients, node.state, child, bl, full.cost.matrix, k, penalty, multiplier), 0)
      min.cost <- min(costs)
      
      if(length(which(costs == min.cost))==1){
        decision <- patients[which(costs == min.cost)]
        # if(verbose){
        #   cat("Single minimum cost belongs to ", decision, "\n", sep="")
        # }
      } else {
#        cat("Tie at node",child,"between",format(patients[which(costs == min.cost)]),"broken randomly\n", sep=" ")
        choices <- which(costs == min.cost)
        choice <- choices[sample.int(length(choices), 1)]
        
        decision <- patients[choice]
        
      }
      node.assocs <- reconstruct.fi(tree, child, decision, node.assocs, tip.assocs, patients, full.cost.matrix, finite.costs, k, penalty, tip.read.counts, verbose)
    }
  }
  return(node.assocs)
}

#' @keywords internal
#' @export calc.costs.fi

calc.costs.fi <- function(child.patient.no, patients, parent.patient, child.node, bl, full.cost.matrix, k, penalty, multiplier=1){
  patient <- patients[child.patient.no]
  out <- full.cost.matrix[child.node, child.patient.no]
  if(parent.patient=="unassigned"){
    if(patient=="unassigned"){
      out <- out + penalty
    } else {
      out <- out + ((1/k)-penalty)*multiplier
    }
  } else {
    if(patient=="unassigned"){
      out <- out + penalty
    } else if(patient == parent.patient){
      out <- out + bl
    } else {
      out <- out + ((1/k)-penalty)*multiplier
    }
  }
  return(out)
}
