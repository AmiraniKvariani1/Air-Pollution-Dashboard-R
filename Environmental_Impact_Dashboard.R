library(shiny)
library(shinydashboard)
library(tidyverse)
library(plotly)
library(readr)

# === Load and prepare data ===

# 1. Global air pollution data
global_air_pollution_dataset <- read_csv("data/Global_Air_Pollution_dataset.csv") |> na.omit()

airPollution <- global_air_pollution_dataset %>%
  group_by(Country) %>%
  summarize(averageAQIvalue = round(mean(`AQI Value`, na.rm=TRUE), 1)) %>%
  arrange(desc(averageAQIvalue))

# 30 largest countries
largest_countries <- c("Russian Federation","Canada","China","United States of America","Brazil",
                       "Australia","India","Argentina","Kazakhstan","Algeria","Democratic Republic of the Congo",
                       "Saudi Arabia","Mexico","Indonesia","Sudan","Libya","Mongolia","Peru","Chad","Niger","Angola",
                       "Mali","South Africa","Colombia","Ethiopia","Mauritania","Egypt","Nigeria","Pakistan","Namibia")

biggest30 <- airPollution %>% filter(Country %in% largest_countries)

# 2. Deaths from air pollution
deaths <- read_csv("data/Share-Deaths-Air-Pollution.csv") |> 
  select(-Code) |> filter(Year != 2020)
names(deaths)[names(deaths) == "Entity"] <- "Country"

# 3. Temperature change
annualTempChange <- read_csv("data/Annual_Surface_Temperature_Change.csv") %>%
  select(-ISO2, -ISO3, -Indicator, -Unit, -Source, -CTS_Code, -CTS_Name, -CTS_Full_Descriptor, -ObjectId) %>%
  pivot_longer(cols = starts_with("F"), names_to = "Year", values_to = "TempChangevalues") %>%
  mutate(Year = as.numeric(gsub("F", "", Year))) %>%
  filter(!Year %in% c(1961:1989, 2020:2025)) %>%
  na.omit()

deaths <- deaths %>% filter(Year %in% annualTempChange$Year)

# Filter countries in both datasets
common_countries <- intersect(unique(deaths$Country), unique(annualTempChange$Country))
deaths <- deaths %>% filter(Country %in% common_countries)
annualTempChange <- annualTempChange %>% filter(Country %in% common_countries)

# Merge both datasets
poluttionresult <- merge(deaths, annualTempChange, by = c("Country", "Year"))
names(poluttionresult)[names(poluttionresult) == 
                         "Deaths - Cause: All causes - Risk: Air pollution - Sex: Both - Age: Age-standardized (Percent)"] <- "Deathpercentage"

# Only keep countries with complete data across years
complete_countries <- poluttionresult %>%
  group_by(Country) %>%
  filter(n_distinct(Year) == max(n_distinct(Year))) %>%
  ungroup()

# G20 subset
g20countries <- complete_countries %>%
  filter(Country %in% c("Argentina","Australia","Brazil","Canada","France","Germany","India","Indonesia",
                        "Italy","Japan","Mexico","Saudi Arabia","South Africa","United Kingdom","United States"))

# 4. Forest data
forest_raw <- read_csv("data/Forest_and_Carbon.csv")
forestdata <- forest_raw %>%
  select(-ISO2, -ISO3, -Unit, -Source, -CTS_Code, -CTS_Name, -CTS_Full_Descriptor,-ObjectId) %>%
  filter(Indicator == "Share of forest area") %>%
  pivot_longer(cols = starts_with("F"), names_to = "Year", values_to = "shareofforestpercentage") %>%
  mutate(Year = as.numeric(gsub("F", "", Year))) %>%
  na.omit()

# Normalize names
forestdata$Country <- recode(forestdata$Country,
                             "Americas" = "United States of America",
                             "Kazakhstan, Rep. of" = "Kazakhstan",
                             "Congo, Dem. Rep. of the" = "Democratic Republic of the Congo",
                             "Ethiopia, The Federal Dem. Rep. of" = "Ethiopia",
                             "Mauritania, Islamic Rep. of" = "Mauritania",
                             "Egypt, Arab Rep. of" = "Egypt",
                             "China, P.R.: Mainland" = "China")

# Forest averages
biggest30c <- forestdata %>%
  filter(Country %in% largest_countries) %>%
  group_by(Country) %>%
  summarize(averageforestshareperc = round(mean(shareofforestpercentage, na.rm=TRUE), 2))

# Merge for forest vs AQI scatter
biggest30new <- merge(biggest30, biggest30c, by = "Country")

# === UI ===
ui <- dashboardPage(
  dashboardHeader(title = "Global Pollution & Environment"),
  dashboardSidebar(
    sidebarMenu(
      menuItem("AQI Bar Chart", tabName = "aqi_chart", icon = icon("bar-chart")),
      menuItem("Death % Over Time", tabName = "death_line", icon = icon("chart-line")),
      menuItem("Temp vs Death %", tabName = "temp_death", icon = icon("dot-circle")),
      menuItem("Forest Share", tabName = "forest_chart", icon = icon("tree")),
      menuItem("AQI vs Forest", tabName = "aqi_forest", icon = icon("globe")),
      menuItem("Top AQI Selector", tabName = "top_aqi", icon = icon("sliders-h")),
      menuItem("Top Forest Selector", tabName = "top_forest", icon = icon("sliders-h"))
    )
  ),
  dashboardBody(
    tabItems(
      tabItem("aqi_chart", plotOutput("aqiBar")),
      tabItem("death_line", plotlyOutput("deathLine")),
      tabItem("temp_death", plotlyOutput("scatterTempDeath")),
      tabItem("forest_chart", plotOutput("forestBar")),
      tabItem("aqi_forest", plotlyOutput("scatterAqiForest")),
      tabItem("top_aqi",
              sliderInput("selectedNumber", "Choose top N countries", 10, min = 5, max = 30),
              plotOutput("topAQIPlot")),
      tabItem("top_forest",
              numericInput("selectedForestN", "Enter number of countries", 10, min = 3, max = 30),
              plotOutput("topForestPlot"))
    )
  )
)

# === SERVER ===
server <- function(input, output) {
  
  output$aqiBar <- renderPlot({
    ggplot(biggest30) + aes(x = reorder(Country, averageAQIvalue), y = averageAQIvalue, fill = Country) +
      geom_bar(stat = "identity") + coord_flip() +
      labs(title = "Average AQI - 30 Largest Countries", x = "Country", y = "Average AQI")
  })
  
  output$deathLine <- renderPlotly({
    p <- ggplot(g20countries) + aes(x=Year, y=Deathpercentage, color=Country) +
      geom_line(size=0.7) +
      labs(title="Death % Over Time", x="Year", y="Death %")
    ggplotly(p)
  })
  
  output$scatterTempDeath <- renderPlotly({
    p <- ggplot(g20countries, aes(x = Deathpercentage, y = TempChangevalues)) +
      geom_point(color="red") +
      geom_smooth(method='lm') +
      labs(title = "Temp Change vs Death %", x = "Death %", y = "Temp Change")
    ggplotly(p)
  })
  
  output$forestBar <- renderPlot({
    ggplot(biggest30c) + aes(x = reorder(Country, averageforestshareperc), y = averageforestshareperc, fill = Country) +
      geom_bar(stat = "identity") + coord_flip() +
      labs(title = "Forest Share - 30 Largest Countries", x = "Country", y = "Forest %")
  })
  
  output$scatterAqiForest <- renderPlotly({
    p <- ggplot(biggest30new, aes(x = averageAQIvalue, y = averageforestshareperc)) +
      geom_point(color="green") +
      geom_smooth(method='lm') +
      labs(title = "AQI vs Forest Share", x = "Average AQI", y = "Forest %")
    ggplotly(p)
  })
  
  output$topAQIPlot <- renderPlot({
    top <- top_n(biggest30, input$selectedNumber, wt = averageAQIvalue)
    ggplot(top) + aes(x = reorder(Country, averageAQIvalue), y = averageAQIvalue, fill = Country) +
      geom_bar(stat = "identity") + coord_flip() +
      labs(title = paste("Top", input$selectedNumber, "Countries by AQI"), x = "Country", y = "AQI")
  })
  
  output$topForestPlot <- renderPlot({
    top <- top_n(biggest30c, input$selectedForestN, wt = averageforestshareperc)
    ggplot(top) + aes(x = reorder(Country, averageforestshareperc), y = averageforestshareperc, fill = Country) +
      geom_bar(stat = "identity") + coord_flip() +
      labs(title = paste("Top", input$selectedForestN, "Countries by Forest Share"), x = "Country", y = "Forest %")
  })
}

# === Run the app ===
shinyApp(ui, server)