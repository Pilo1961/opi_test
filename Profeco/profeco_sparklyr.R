library(sparklyr)
library(dplyr)
library(ggplot2)

sc <- spark_connect(master = "local", version = "2.3")
spark_web(sc)

path <-  "D:\\DummyDir\\opi_test\\profeco.pdf\\all_data.csv"
data_sp <- spark_read_csv(sc, path)

### Procesamiento de datos
# numero de registros
data_sp %>% sdf_nrow()

# numero de categorias
query <- data_sp %>% 
  select(categoria) %>% 
  distinct() %>% 
  count() 

query %>% collect()

# numero de cadenas comericales monitoreas
query <- data_sp %>% 
  select(cadenaComercial) %>% 
  distinct() %>% 
  count()

query %>%  collect()

# Calidad de datos e inconsistencias


# Productos monitoreados por entidad
query <- data_sp %>% 
  select(producto, estado) %>% 
  group_by(estado, producto) %>% 
  summarise(prod_count = n()) 

top_1 <- query %>% 
 collect()%>% 
  group_by(estado) %>% 
  top_n(1, prod_count) %>% 
  arrange(estado)

write.csv(top_1, "top.csv", row.names = FALSE)

# Cadena comercial con mas productos monitoreados
query <- data_sp %>% 
  select(producto, cadenaComercial) %>% 
  group_by(cadenaComercial, producto) %>% 
  summarise(prod_count = n()) %>% 
  ungroup() %>% 
  group_by(cadenaComercial) %>% 
  summarise(num_prod = n())

top_cadena <- query %>% 
  collect() %>% 
  arrange(desc(num_prod))

write.csv(top_3, "top.csv", row.names = FALSE)

### Analisis Exploratorio
# Seleccion de canasta basica
omit_catergories <- c("DETERGENTES Y PRODUCTOS SIMILARES",
                      "UTENSILIOS DOMESTICOS",
                      "MATERIAL ESCOLAR",
                      "ARTS. DE ESPARCIMIENTO (JUGUETES)",
                      "CIGARRILLOS",
                      "APARATOS ELECTRONICOS",
                      "MUEBLES DE COCINA",
                      "VINOS Y LICORES",
                      "ARTS. PARA EL CUIDADO PERSONAL",
                      "APARATOS ELECTRICOS",
                      "ACCESORIOS DOMESTICOS",
                      "CERVEZA")

# filtra y cuenta productos
q <- data_sp %>% 
  select(categoria, producto) %>% 
  filter(! categoria %in% omit_catergories) %>% 
  group_by(producto) %>% 
  summarise(counts = n()) %>% 
  arrange(desc(counts))

# genera la lista de la canasta basica
canasta_basica <- q %>% collect()%>% top_n(40, counts)
canasta_basica <- canasta_basica %>% pull(producto)

# Selecciona los registros de la canasta basica y calcula el precio promedio
q <- data_sp %>% 
  select(producto, precio, municipio) %>% 
  filter(producto %in% canasta_basica) %>% 
  group_by(municipio) %>% 
  summarise(avg_price = mean(precio),
            sd_price = sd(precio),
            count = n())

# Encuentra la ciudad mas barata y mas cara
precios_canasta <- q %>% collect()
precios_canasta <- precios_canasta %>% filter(count> 1000)
precios_canasta  %>% slice(which.max(avg_price))
precios_canasta  %>% slice(which.min(avg_price))

# Hay algun patron estacional entre años
q <- data_sp %>% 
  select(producto, precio, estado, fechaRegistro) %>% 
  filter(producto %in% canasta_basica) %>% 
  mutate(char_date = as.character(fechaRegistro),
         list_date = split(char_date,"-")) %>% 
  sdf_separate_column("list_date", into = c("year", "month","rest")) %>% 
  select(-rest,-list_date,-char_date) %>% 
  mutate(month = as.integer(month),
         year = as.integer(year)) %>% 
  group_by(year, month) %>% 
  summarise(avg_price = mean(precio))
  
temp <- q  %>% collect()
temp <- temp %>% 
  arrange(year, month)

acf(temp$avg_price,lag.max=12,plot=TRUE)
ggplot(data=temp, aes(x=month, y=avg_price, colour=as.factor(year)))+geom_point()+ggtitle("Precios Canasta Báscia")

# Cual es el estado mas caro y en que mes
q <- data_sp %>% 
  select(producto, precio, estado, fechaRegistro) %>% 
  filter(producto %in% canasta_basica) %>% 
  mutate(char_date = as.character(fechaRegistro),
         list_date = split(char_date,"-")) %>% 
  sdf_separate_column("list_date", into = c("year", "month","rest")) %>% 
  select(-rest,-list_date,-char_date) %>% 
  mutate(month = as.integer(month),
         year = as.integer(year)) %>% 
  group_by(estado, month) %>% 
  summarise(avg_price = mean(precio))

estado_caro <- q %>% collect()
estado_caro %>% arrange(desc(avg_price))

#disconect session
spark_disconnect_all()
