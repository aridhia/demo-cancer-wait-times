####################
###### SERVER ######
####################


server <- function(input, output, session) {
  
  names(xl_sheets) <- list.files("./datafiles/")
  dfs <- reactiveValues(merged = 0, by_area = 0, regions = 0, quarts = 0, types_of_canc = 0, name = 0, nat_avg = 0)
  
  # map before choosing a sheet - grey
  b <- leaflet(options = leafletOptions(minZoom = 5.6, maxZoom = 5.6)) %>%
    addTiles() %>%
    addPolygons(data = map_gsdf, 
                layerId= map_gsdf$scn16cd, 
                color = "#444444", weight = 1, smoothFactor = 0.5,
                popup = paste0("<b>", map_gsdf$scn16nm,"</b>"),
                opacity = 1.0, fillOpacity = 0.5,
                highlightOptions = highlightOptions(color = "white", weight = 2, bringToFront = TRUE))
  # Render the map
  output$map <- renderLeaflet(b)
  
  # When the user selects a sheet
  observeEvent(input$sheet,{
    
    if (input$sheet != ""){
      
      list_of_sheets <- names(xl_sheets) %>%
        map(~paste0("./datafiles/", .))%>%
        map(~read_rm_sheet(., input$sheet))%>%
        map(add_ons_id)

      merged <- do.call('rbind', list_of_sheets)
      merged[is.na(merged)] = "N/A"
      dfs$merged <- merged
      dfs$by_area <- NULL

      areas <- merged[[1]] %>%
        unique()

      if (length(areas) > 10){
        names(areas) <- c('West Midlands', 'South East Coast', 'London', 'North West', 'South Central', 'North East',
                          'Yorkshire and the Humber', 'East Midlands', 'East of England', 'South West', 'N/A')
      }
      else{
        names(areas) <- c('West Midlands', 'South East Coast', 'London', 'North West', 'South Central', 'North East',
                          'Yorkshire and the Humber', 'East Midlands', 'East of England', 'South West')
      }
      
      
      dfs$regions <- areas

      time_quarters <- merged$time_period %>%
        unique()
      
      dfs$quarts <- time_quarters
      
      # Upadate the regions and quarter options to adapt to the selected sheet
      updateSelectizeInput(session, 'regions', choices = names(areas))
      updateSelectizeInput(session, 'quarter', choices = dfs$quarts)
      
      # Render data table of the inputted information
      output$sheet <- DT::renderDataTable(merged,options = list( targets = '_all'))
      
      percentage_name <- names(merged)[[match('total',names(merged)) + 3]]

      averages <- merged %>%
        group_by(ons_area_id) %>%
        summarise(average_time = mean(.data[[percentage_name]])) %>%
        # .[map_gsdf@data$scn16cd,] %>%
        # .[-11,] %>%
        select(average_time) %>%
        pull( ., average_time) %>%
        round(., 2)

      map_gsdf$data$average <- as.factor(averages)

      min <- round(min(averages), 0) - 1
      max <- round(max(averages), 0) + 1
      
      if(is.na(min)) min <- 1
      if(is.na(max)) max <- 2
      
      # Color palette according to range between min and max
      pal <- colorNumeric(
        palette = "YlGnBu",
        domain = min:max
      )
      
      legend_title <- str_replace_all(percentage_name,'_',' ') %>%
        str_replace_all(., 'percentage', '%')
      
      dfs$name <- legend_title
      
      # map once the sheet has been selected
      b <- leaflet(options = leafletOptions(minZoom = 5.6, maxZoom = 5.6)) %>%
        addTiles() %>%
        addPolygons(data = map_gsdf,
                    layerId= map_gsdf$scn16cd,
                    color = ~pal(averages), weight = 1, smoothFactor = 0.5,
                    popup = paste0("<b>",map_gsdf$scn16nm,"<br></b>", map_gsdf$data$average, "%"),
                    opacity = 1.0, fillOpacity = 0.7,
                    highlightOptions = highlightOptions(color = "yellow", weight = 2, bringToFront = TRUE)) %>%
        addLegend( "bottomright", pal = pal, values = averages, title = legend_title, labFormat = labelFormat(suffix = "%"),
                   opacity = 1
          
        )
      
      nat_avg <- (sum(merged[[which(names(merged)=='total')+1]]) / sum(merged$total)) * 100
      dfs$nat_avg <- nat_avg
      # Render map
      output$map <- renderLeaflet(b)
      # Empty plot - needs region selection
      output$plot <- renderPlot({})
      # Render text with national average
      output$national_avg <- renderText({paste("<b> Overall national average of ",dfs$name, ": </b>",as.character(round(nat_avg, 2)), "%")})
      
      if (grepl("BY CANCER", input$sheet)){
        cancer_field <- names(merged)[[match('total',names(merged)) - 1]]
        cancer_types <- merged[[cancer_field]] %>%
          unique()
        
        dfs$types_of_canc <- cancer_types
        
        updateSelectizeInput(session, 'cancerType', choices = dfs$types_of_canc)
      }
      }
  })
  
  # When the user selects a region
  observeEvent(input$regions,{
    
    if (input$regions != ""){
      
      tmp <- dfs$merged[which(dfs$merged[[1]] == dfs$regions[[input$regions]]),]
      dfs$by_area <- tmp
      
      time_quarters <- tmp$time_period %>%
        unique()
      
      # Update quarter information
      updateSelectizeInput(session, 'quarter', choices = time_quarters)
      
      if (grepl("BY CANCER", input$sheet)){
        updateSelectizeInput(session, 'cancerType', choices = dfs$types_of_canc)
      }
      
      # Update data table
      output$sheet <- DT::renderDataTable(tmp, options = list( targets = '_all'))
      
      # Render plot
      output$plot <- renderPlot(plots(tmp, dfs$name, dfs$nat_avg))
    }
  })
  
  observeEvent(input$cancerType,{
    
    if (input$cancerType != ""){
      
      if (is.null(dfs$by_area)){
        
        if (input$quarter != ""){
          tmp <- dfs$merged[which(dfs$merged[[match('total',names(dfs$merged)) - 1]] == input$cancerType),] %>%
            .[which(.[['time_period']] == input$quarter),]
        }
        else{
          tmp <- dfs$merged[which(dfs$merged[[match('total',names(dfs$merged)) - 1]] == input$cancerType),]
        }
        
        output$sheet <- DT::renderDataTable(tmp,options = list( targets = '_all'))
      }
      else{
        if (input$quarter != ""){
          tmp <- dfs$by_area[which(dfs$by_area[[match('total',names(dfs$by_area)) - 1]] == input$cancerType),] %>%
            .[which(.[['time_period']] == input$quarter),]
        }
        else{
          tmp <- dfs$by_area[which(dfs$by_area[[match('total',names(dfs$by_area)) - 1]] == input$cancerType),]
        }
        
        output$sheet <- DT::renderDataTable(tmp,options = list( targets = '_all'))
        
        output$plot <- renderPlot(plots(tmp, dfs$name, dfs$nat_avg))
      }
      
    }
  })
  
  observeEvent(input$quarter,{
    
    if (input$quarter != ""){
      
      if (is.null(dfs$by_area)){
        
        if (input$cancerType != ""){
          tmp <- dfs$merged[which(dfs$merged[[match('total',names(dfs$merged)) - 1]] == input$cancerType),] %>%
            .[which(.[['time_period']] == input$quarter),]
        }
        else{
          tmp <- dfs$merged[which(dfs$merged[['time_period']] == input$quarter),]
        }
        
        output$sheet <- DT::renderDataTable(tmp,options = list( targets = '_all'))
      }
      else{
        if (input$cancerType != ""){
          tmp <- dfs$by_area[which(dfs$by_area[[match('total',names(dfs$by_area)) - 1]] == input$cancerType),] %>%
            .[which(.[['time_period']] == input$quarter),]
        }
        else{
          tmp <- dfs$by_area[which(dfs$by_area[['time_period']] == input$quarter),]
        }
        
        output$sheet <- DT::renderDataTable(tmp,options = list( targets = '_all'))
        
        output$plot <- renderPlot(plots(tmp, dfs$name, dfs$nat_avg))
      }
    }
  })
}
