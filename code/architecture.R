require(tidyverse)
require(wesanderson)
require(ggbeeswarm)
require(ggrepel)
setwd(paste0(dirname(rstudioapi::getActiveDocumentContext()$path),"/.."))

####################################
### Architecture Simulation Data ###
####################################

# Mapping Results, Default settings: Group = 1000 bp, CI = +150 markers
load(file = "data/File_S3.RData")
dat.inbred.pca <- simulation.metrics.df %>%
  tidyr::separate(col = sim,
                  into = c("nQTL","Rep","h2","MAF","effect_range","strain_set"), 
                  sep = "_", remove = F) %>%
  tidyr::separate(col = QTL,
                  into = c("CHROM","POS"), 
                  sep = ":", remove = F) %>%
  dplyr::mutate(h2 = as.factor(h2),
                nQTL = as.factor(nQTL),
                POS = as.numeric(POS),
                startPOS = as.numeric(startPOS),
                peakPOS = as.numeric(peakPOS),
                endPOS = as.numeric(endPOS),
                interval.var.exp  = as.numeric(interval.var.exp),
                Simulated.QTL.VarExp = as.numeric(Simulated.QTL.VarExp), 
                peak_id = as.numeric(peak_id),
                BETA = as.numeric(BETA),
                Effect = as.numeric(Effect),
                Frequency = as.numeric(Frequency),
                # log10p = dplyr::if_else(Simulated == FALSE,
                #                         true = interval.log10p,
                #                         false = log10p), # false discoveries inherit the log10p value of the peak marker for the interval
                # log10p = as.numeric(log10p),
                interval_size = as.numeric(interval_size),
                aboveBF = dplyr::case_when(aboveBF == 1 ~ TRUE, 
                                           aboveBF == 0 ~ FALSE,
                                           is.na(aboveBF) ~ TRUE), # false discoveries by definition exceed significance threshold
                aboveBF = as.factor(aboveBF)) %>%
  dplyr::filter(CHROM != 7)
dat.inbred.pca$nQTL <- factor(dat.inbred.pca$nQTL, 
                              levels = c("1","5","10","25","50"))

h2.pal <- wes_palette("Darjeeling1", 4)[c(1,4,3,2)]
nQTL.pal <- wes_palette("Darjeeling2", 5)
options(dplyr.summarise.inform = FALSE)


gamma.supp <- dat.inbred.pca %>%
  dplyr::filter(Simulated == TRUE) %>%
  ggplot(., mapping = aes(x = Simulated.QTL.VarExp*100)) + 
  theme_bw() + 
  geom_histogram(bins = 100) + 
  facet_grid(nQTL ~ h2, scales = "free_y") + 
  theme(panel.grid = element_blank()) + 
  labs(x = "Simulated Variance Explained by QTL (%)",
       y = "Frequency")
ggsave(gamma.supp, filename = "plots/supp.fig.3.png", height = 5, width = 5)



designations <- dat.inbred.pca %>%
  droplevels() %>%
  dplyr::mutate(designation = case_when(Simulated == TRUE & Detected == TRUE & aboveBF == TRUE ~ "Detected.CV",
                                        Simulated == TRUE & Detected == FALSE & aboveBF == FALSE ~ "Missed.CV",
                                        Simulated == TRUE & Detected == TRUE & aboveBF == FALSE ~ "CV.Not.Significant.In.Interval",
                                        Simulated == FALSE & Detected == TRUE & aboveBF == TRUE ~ "False.Discovery")) %>%
  tidyr::separate(col = detected.peak,
                  into = c("peak.CHROM","peak.POS"), 
                  sep = ":", remove = F) %>%
  dplyr::mutate(QTL.v.peak = abs(as.numeric(POS)-as.numeric(peak.POS))) %>%
  dplyr::group_by(h2, algorithm, nQTL, designation, Rep) %>%
  dplyr::summarise(n = n()) %>%
  tidyr::pivot_wider(names_from = designation, values_from = n)
designations[is.na(designations)] <- 0


#################
### Figure 2A ###
#################
Power <- designations %>%
  dplyr::mutate(Detected = Detected.CV + CV.Not.Significant.In.Interval + False.Discovery,
                Simulated = Detected.CV + CV.Not.Significant.In.Interval + Missed.CV) %>%
  dplyr::filter(Simulated != 0) %>%
  dplyr::mutate(Power = Detected.CV/Simulated,
                Artefact.Rate = False.Discovery/Detected,
                Detected.CV.NS.Rate = CV.Not.Significant.In.Interval/Detected) %>%
  dplyr::group_by(algorithm, h2, nQTL) %>%
  dplyr::summarise(mean.Power = mean(Power),
                   sd.Power = sd(Power)) %>%
  dplyr::mutate(b = mean.Power + sd.Power,
                a = mean.Power - sd.Power,
                nQTL = as.factor(nQTL),
                ymax = if_else(condition = b > 1, 
                               true = 1-mean.Power, 
                               false = sd.Power),
                ymin = if_else(condition = a < 0, 
                               true = (0-mean.Power)*-1, 
                               false = sd.Power)) %>%
  dplyr::select(-a,-b)

# aggregated across heritability
designations %>%
  dplyr::mutate(Detected = Detected.CV + CV.Not.Significant.In.Interval + False.Discovery,
                Simulated = Detected.CV + CV.Not.Significant.In.Interval + Missed.CV) %>%
  dplyr::filter(Simulated != 0) %>%
  dplyr::mutate(Power = Detected.CV/Simulated,
                Artefact.Rate = False.Discovery/Detected,
                Detected.CV.NS.Rate = CV.Not.Significant.In.Interval/Detected) %>%
  dplyr::group_by(algorithm, nQTL) %>%
  dplyr::summarise(mean.Power = mean(Power),
                   sd.Power = sd(Power))


A <- ggplot(Power, mapping = aes(x = nQTL, y = mean.Power, colour = h2, 
                                 group = interaction(h2,algorithm))) +
  theme_bw(base_size = 11) +
  geom_line(position=position_dodge(width=0.2)) +
  geom_point(position = position_dodge(width = 0.2)) +
  geom_errorbar(data = Power, 
                mapping = aes(y = mean.Power, ymax = mean.Power+ymax, ymin = mean.Power-ymin),
                width = 0.2,
                position=position_dodge(width=0.2)) +
  scale_colour_manual(values = h2.pal, name = expression(italic(h^2))) +
  ylim(c(0,1)) + 
  theme(strip.text = element_text(size = 8),
        legend.position = "top",
        panel.grid.major = element_blank(),
        panel.grid.minor = element_blank()) +
  labs(x = "Number of Supporting QTL",
       y = "Power")


#################
### Figure 2B ###
#################
FDR <- designations %>%
  dplyr::mutate(Detected = Detected.CV + CV.Not.Significant.In.Interval + False.Discovery,
                Simulated = Detected.CV + CV.Not.Significant.In.Interval + Missed.CV) %>%
  dplyr::filter(Simulated != 0) %>%
  dplyr::mutate(Power = Detected.CV/Simulated,
                Artefact.Rate = False.Discovery/Detected,
                Detected.CV.NS.Rate = CV.Not.Significant.In.Interval/Detected) %>%
  dplyr::filter(Detected != 0) %>%
  dplyr::group_by(algorithm, nQTL, h2) %>%
  dplyr::summarise(mean.Artefact = mean(Artefact.Rate),
                   sd.Artefact.Rate = sd(Artefact.Rate)) %>%
  dplyr::mutate(b = mean.Artefact + sd.Artefact.Rate,
                a = mean.Artefact - sd.Artefact.Rate,
                nQTL = as.factor(nQTL),
                ymax = if_else(condition = b > 1, 
                               true = 1-mean.Artefact, 
                               false = sd.Artefact.Rate),
                ymin = if_else(condition = a < 0, 
                               true = (0-mean.Artefact)*-1, 
                               false = sd.Artefact.Rate)) %>%
  dplyr::select(-a,-b)

designations %>%
  dplyr::mutate(Detected = Detected.CV + CV.Not.Significant.In.Interval + False.Discovery,
                Simulated = Detected.CV + CV.Not.Significant.In.Interval + Missed.CV) %>%
  dplyr::filter(Simulated != 0) %>%
  dplyr::mutate(Power = Detected.CV/Simulated,
                Artefact.Rate = False.Discovery/Detected,
                Detected.CV.NS.Rate = CV.Not.Significant.In.Interval/Detected) %>%
  dplyr::filter(Detected != 0) %>%
  dplyr::group_by(algorithm, nQTL) %>%
  dplyr::summarise(mean.Artefact = mean(Artefact.Rate),
                   sd.Artefact.Rate = sd(Artefact.Rate))


B <- ggplot(FDR, mapping = aes(x = nQTL, y = mean.Artefact , colour = h2, 
                               group = interaction(h2,algorithm))) +
  theme_bw(base_size = 11) +
  geom_line(position=position_dodge(width=0.2)) +
  geom_point(position = position_dodge(width = 0.2)) +
  geom_errorbar(data = FDR, 
                mapping = aes(y = mean.Artefact , ymax = mean.Artefact +ymax, ymin = mean.Artefact -ymin),
                width = 0.2,
                position=position_dodge(width=0.2)) +
  scale_colour_manual(values = h2.pal, name = expression(italic(h^2))) +
  ylim(c(0,1)) + 
  theme(strip.text = element_text(size = 8),
        legend.position = "top",
        panel.grid.major = element_blank(),
        panel.grid.minor = element_blank()) +
  labs(x = "Number of Supporting QTL",
       y = "FDR")


#################
### Figure 2C ###
#################
VE.plot <- dat.inbred.pca %>%
  dplyr::filter(Simulated == TRUE) %>% # true positives
  droplevels() %>%
  dplyr::mutate(designation = as.factor(case_when(aboveBF == TRUE & top.hit == TRUE ~ "Top Within Region",
                                                  aboveBF == TRUE & top.hit == FALSE ~ "Significant",
                                                  aboveBF == FALSE & Detected == TRUE ~ "Not Significant Association; Within QTL Region",
                                                  aboveBF == FALSE & Detected == FALSE ~ "Causal Variant Not Detected"))) %>%
  dplyr::mutate(nQTL = paste0(nQTL," QTL"))

VE.plot$designation <- factor(VE.plot$designation, 
                              levels = c("Top Within Region","Significant",
                                         "Not Significant Association; Within QTL Region","Causal Variant Not Detected"))
VE.plot$nQTL <- factor(VE.plot$nQTL, levels = c("1 QTL","5 QTL","10 QTL","25 QTL","50 QTL"))
C <-  ggplot(VE.plot, mapping = aes(x = designation, y = Simulated.QTL.VarExp*100, colour = designation)) + 
  theme_bw(base_size = 11) +
  geom_boxplot(outlier.alpha = 0.1) + 
  facet_grid(nQTL~h2, scales = "free", space = "free") + 
  scale_colour_manual(values = wes_palette(name = "Moonrise2"), name = "Association Type") + 
  theme(panel.grid = element_blank(),
        axis.text.x = element_blank(),
        axis.ticks.x = element_blank(),
        axis.title.x = element_blank()) + 
  labs(y = "Simulated Variance Explained by QTL (%)")

#####################
# STATISTICS FOR 1C #
#####################
var.exp.stats.nested <- VE.plot %>%
  dplyr::group_by(h2, nQTL) %>%
  tidyr::nest()

Var.Exp.TukeyHSD <- function(data, h2, nQTL){
  stat <- aov(data = data, formula = Simulated.QTL.VarExp*100 ~ designation)
  TukeyHSD(stat)
}
purrr::pmap(list(var.exp.stats.nested$data,
                 var.exp.stats.nested$h2,
                 var.exp.stats.nested$nQTL),
            Var.Exp.TukeyHSD)



var.exp.stats.nested.designations <- VE.plot %>%
  dplyr::group_by(designation) %>%
  tidyr::nest()
Var.Exp.TukeyHSD.Designation <- function(data, designation){
  stat <- aov(data = data, formula = Simulated.QTL.VarExp*100 ~ h2 + nQTL)
  tukey <- TukeyHSD(stat)
  data.frame(tukey[[1]]) %>%
    dplyr::mutate(contrast = row.names(.)) %>%
    dplyr::select(p.adj, contrast) %>%
    tidyr::separate(contrast, c("level1","level2"), sep = "-") %>%
    tidyr::pivot_wider(names_from = level2, values_from = p.adj) %>%
    dplyr::mutate(designation = designation)
  
  data.frame(tukey[[2]]) %>%
    dplyr::mutate(contrast = row.names(.)) %>%
    dplyr::select(p.adj, contrast) %>%
    tidyr::separate(contrast, c("level1","level2"), sep = "-") %>%
    tidyr::pivot_wider(names_from = level2, values_from = p.adj)%>%
    dplyr::mutate(designation = designation)
}
purrr::map2(var.exp.stats.nested.designations$data,
            var.exp.stats.nested.designations$designation,
            Var.Exp.TukeyHSD.Designation)


#################
### Figure 2 ####
#################
AB <- cowplot::plot_grid(A + theme(legend.position = "none"),
                         B + theme(legend.position = "none"),
                         nrow = 1,
                         labels = c("A","B"), 
                         align = "hv", axis = "b", 
                         rel_widths = c(1,1))
AB.legend <- cowplot::get_legend(A)
AB.2 <- cowplot::plot_grid(AB, AB.legend, nrow = 2,
                           rel_heights = c(8,1))

C.legend <- cowplot::get_legend(C)

ABC <- cowplot::plot_grid(AB.2, 
                          C + 
                            theme(legend.position = "bottom") + 
                            guides(colour = guide_legend(nrow = 2)), nrow = 2, 
                          rel_heights = c(1,2), labels = c("","C"))
ggsave(plot = ABC + theme(plot.background = element_rect(fill = "white",colour = NA)), filename = "plots/figure.2.png", height = 6, width = 7.5)
ggsave(plot = ABC + theme(plot.background = element_rect(fill = "white",colour = NA)), filename = "plots/figure.2.pdf", height = 6, width = 7.5)


# Summary Tables of Plotted Values
# Figure 2A
designations %>%
  dplyr::mutate(Detected = Detected.CV + CV.Not.Significant.In.Interval + False.Discovery,
                Simulated = Detected.CV + CV.Not.Significant.In.Interval + Missed.CV) %>%
  dplyr::filter(Simulated != 0) %>%
  dplyr::mutate(Power = Detected.CV/Simulated,
                Artefact.Rate = False.Discovery/Detected,
                Detected.CV.NS.Rate = CV.Not.Significant.In.Interval/Detected) %>%
  dplyr::filter(Detected != 0) %>%
  dplyr::group_by(nQTL, h2) %>%
  dplyr::summarise(mean.Power = mean(Power),
                   sd.Power = sd(Power),
                   value = paste(round(mean.Power,2),
                                 round(sd.Power,2),
                                 sep = " ± ")) %>%
  dplyr::select(nQTL, h2, value) %>%
  tidyr::pivot_wider(names_from = h2, values_from = value)


# Figure 2B
designations %>%
  dplyr::mutate(Detected = Detected.CV + CV.Not.Significant.In.Interval + False.Discovery,
                Simulated = Detected.CV + CV.Not.Significant.In.Interval + Missed.CV) %>%
  dplyr::filter(Simulated != 0) %>%
  dplyr::mutate(Power = Detected.CV/Simulated,
                Artefact.Rate = False.Discovery/Detected,
                Detected.CV.NS.Rate = CV.Not.Significant.In.Interval/Detected) %>%
  dplyr::filter(Detected != 0) %>%
  dplyr::group_by(nQTL, h2) %>%
  dplyr::summarise(mean.AR = mean(Artefact.Rate),
                   sd.AR = sd(Artefact.Rate),
                   value = paste(round(mean.AR,2),
                                 round(sd.AR,2),
                                 sep = " ± ")) %>%
  dplyr::select(nQTL, h2, value) %>%
  tidyr::pivot_wider(names_from = h2, values_from = value)

VE.plot %>%
  dplyr::filter(designation == "Top Within Region") %>%
  dplyr::group_by(h2, nQTL) %>%
  dplyr::summarise(median = median(Simulated.QTL.VarExp*100)) %>%
  dplyr::arrange(median)

VE.plot %>%
  dplyr::filter(designation == "Causal Variant Not Detected") %>%
  dplyr::group_by(h2, nQTL) %>%
  dplyr::summarise(median = median(Simulated.QTL.VarExp*100)) %>%
  dplyr::arrange(median)
