#' A simple features object of the world land map
#'
#' An integrated land map
#'
#' @format A simple features object
#' \describe{
#'   \item{featurecla}{Land area}
#'   \item{scalerank}{Scale rank of the land feature}
#'   \item{min_zoom}{Minimum zoom level at which the feature is displayed}
#'   \item{geometry}{Geometry unit}
#' }
#' @importFrom utils data
#' @seealso [rnaturalearth::ne_download()]
#' @source \code{rnaturalearth::ne_download(scale = 110,type = 'land',category = 'physical',returnclass = "sf")}
"WorldLandMap"
