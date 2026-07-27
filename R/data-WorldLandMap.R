#' A simple features object of the world land map
#'
#' An integrated land map
#'
#' @format A simple features object
#' \describe{
#'   \item{featurecla}{Land area}
#'   \item{geometry}{Geometry unit}
#' }
#' @importFrom utils data
#' @source \code{rnaturalearth::ne_download(scale = 110,type = 'land',category = 'physical',returnclass = "sf")}
"WorldLandMap"
