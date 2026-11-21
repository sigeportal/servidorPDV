unit Produtos.Controller;

interface

uses
  Horse,
  Horse.Commons,
  Horse.GBSwagger,
  Classes,
  SysUtils,
  System.Json,
  DB,
  UnitConnection.Model.Interfaces,
  DataSet.Serialize, UnitNiveis.Model, System.Generics.Collections;

type
  TProdutosController = class
    class procedure Registrar;
    class procedure Get(Req: THorseRequest; Res: THorseResponse; Next: TProc);
    class procedure GetProdutoPorCodigo(Req: THorseRequest; Res: THorseResponse; Next: TProc);
    class procedure GetCategorias(Req: THorseRequest; Res: THorseResponse; Next: TProc);
    class procedure GetFotoProduto(Req: THorseRequest; Res: THorseResponse; Next: TProc);
    class procedure GetFotoCategoria(Req: THorseRequest; Res: THorseResponse; Next: TProc);
    class procedure GetGradesProduto(Req: THorseRequest; Res: THorseResponse; Next: TProc);
    class procedure GetGradeProduto(Req: THorseRequest; Res: THorseResponse; Next: TProc);
  private
    class function BuscaNiveisProduto(CodPro: integer): TJsonArray; static;
    class procedure GetNiveisProduto(Req: THorseRequest; Res: THorseResponse;
      Next: TProc); static;
    class procedure GetProdutosPorGrupo(Req: THorseRequest;
      Res: THorseResponse); static;
  end;

implementation

{ TProdutosController }

uses 
	UnitFuncoesComuns, 
  UnitTabela.Helpers,
  UnitDatabase,
  UnitProducao.Service,
  UnitProdutos.Model, UnitGrades.Model;

class procedure TProdutosController.Get(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Query    : iQuery;
  Categoria: integer;
  Busca: string;
  TipoFiltro: string;
  TipoNorm: string;
  IncluirMP: Boolean;
  aJson    : TJSONArray;
  oJson    : TJSONObject;
  grupo: Integer;
begin
  Query := TDatabase.Query;
  aJson := TJSONArray.Create;
  Query.Clear;
  Busca := Trim(Req.Query.Items['busca']);
  IncluirMP := Req.Query.ContainsKey('incluir_mp') and
    SameText(Trim(Req.Query.Items['incluir_mp']), 'true');
  TipoFiltro := '';
  if Req.Query.ContainsKey('tipo') then
    TipoFiltro := Trim(Req.Query.Items['tipo']);

  Query.Add('SELECT P.PRO_CODIGO, P.PRO_NOME, P.PRO_CODBARRA, P.PRO_VALORV,');
  Query.Add('       COALESCE(P.PRO_VALORC, 0) PRO_VALORC, COALESCE(P.PRO_VALORCM, 0) PRO_VALORCM,');
  Query.Add('       COALESCE(P.PRO_QUANTIDADE, 0) PRO_QUANTIDADE,');
  Query.Add('       COALESCE(P.PRO_TIPO, '''') PRO_TIPO, COALESCE(P.PRO_EMBALAGEM, '''') PRO_EMBALAGEM,');
  Query.Add('       COALESCE(G.GRU_CODIGO, P.PRO_GRU, 0) GRU_CODIGO,');
  Query.Add('       COALESCE(G.GRU_G1, 0) GRU_G1, COALESCE(G1.G1_NOME, '''') G1_NOME,');
  Query.Add('       (SELECT FIRST 1 GRA_CODIGO FROM GRADES WHERE GRA_PRO = P.PRO_CODIGO) GRA_CODIGO');
  Query.Add('FROM PRODUTOS P');
  Query.Add('LEFT JOIN GRUPOS G ON P.PRO_GRU = G.GRU_CODIGO');
  Query.Add('LEFT JOIN GRUPO_1 G1 ON G1.G1_CODIGO = G.GRU_G1');
  Query.Add('WHERE COALESCE(P.PRO_ESTADO, ''ATIVO'') = ''ATIVO''');

  if not TipoFiltro.IsEmpty then
  begin
    if not SameText(TipoFiltro, 'TODOS') then
    begin
      TipoNorm := TProducaoService.NormalizarTipoProduto(TipoFiltro);
      Query.Add('AND COALESCE(NULLIF(UPPER(TRIM(P.PRO_TIPO)), ''''), ''REVENDA'') = :TIPO_PROD');
      Query.AddParam('TIPO_PROD', TipoNorm);
    end;
  end
  else if not IncluirMP then
  begin
    Query.Add('AND COALESCE(NULLIF(UPPER(TRIM(P.PRO_TIPO)), ''''), ''REVENDA'') NOT IN (''MP'', ''MATERIA_PRIMA'', ''MATERIA-PRIMA'')');
  end;

  if Req.Query.Count > 0 then
  begin
    if Req.Query.ContainsKey('categoria') then
    begin
      Categoria := Req.Query.Items['categoria'].ToInteger;
      Query.Add('AND COALESCE(G.GRU_CODIGO, P.PRO_GRU) = :SUBGRUPO');
      Query.AddParam('SUBGRUPO', Categoria);
    end;
    if Req.Query.ContainsKey('grupo') then
    begin
      grupo := Req.Query.Items['grupo'].ToInteger;
      Query.Add('AND G.GRU_G1 = :GRUPO');
      Query.AddParam('GRUPO', grupo);
    end;
  end;

  if Busca <> '' then
  begin
    Query.Add('AND (UPPER(P.PRO_NOME) LIKE :BUSCA OR CAST(P.PRO_CODIGO AS VARCHAR(20)) LIKE :BUSCA OR UPPER(COALESCE(P.PRO_CODBARRA, '''')) LIKE :BUSCA)');
    Query.AddParam('BUSCA', '%' + UpperCase(Busca) + '%');
  end;

  Query.Add('ORDER BY P.PRO_NOME');
  Query.Open();
  Query.DataSet.First;
  while not Query.DataSet.Eof do
  begin
    TipoNorm := TProducaoService.NormalizarTipoProduto(Query.DataSet.FieldByName('PRO_TIPO').AsString);
    oJson     := TJSONObject.Create;
    oJson.AddPair('codigo', TJSONNumber.Create(Query.DataSet.FieldByName('PRO_CODIGO').AsInteger));
    oJson.AddPair('nome', Query.DataSet.FieldByName('PRO_NOME').AsString);
    oJson.AddPair('codbarra', Query.DataSet.FieldByName('PRO_CODBARRA').AsString);
    oJson.AddPair('valor', TJSONNumber.Create(Query.DataSet.FieldByName('PRO_VALORV').AsCurrency));
    oJson.AddPair('valorc', TJSONNumber.Create(Query.DataSet.FieldByName('PRO_VALORC').AsFloat));
    oJson.AddPair('valorcm', TJSONNumber.Create(Query.DataSet.FieldByName('PRO_VALORCM').AsFloat));
    oJson.AddPair('quantidade', TJSONNumber.Create(Query.DataSet.FieldByName('PRO_QUANTIDADE').AsFloat));
    oJson.AddPair('tipo', TipoNorm);
    oJson.AddPair('unidade', TProducaoService.NormalizarUnidade(Query.DataSet.FieldByName('PRO_EMBALAGEM').AsString));
    oJson.AddPair('categoria', TJSONNumber.Create(Query.DataSet.FieldByName('GRU_CODIGO').AsInteger));
    oJson.AddPair('grade', TJSONNumber.Create(Query.DataSet.FieldByName('GRA_CODIGO').AsInteger));
    oJson.AddPair('grupo', TJSONNumber.Create(Query.DataSet.FieldByName('GRU_G1').AsInteger));
    oJson.AddPair('g1_nome', Query.DataSet.FieldByName('G1_NOME').AsString);
    aJson.AddElement(oJson);
    Query.DataSet.Next;
  end;
  Res.Send<TJSONArray>(aJson);
end;

class procedure TProdutosController.GetCategorias(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Query    : iQuery;
  Categoria: string;
  aJson    : TJSONArray;
  oJson    : TJSONObject;
begin
  Query := TDatabase.Query;
  Query.Clear;
  Query.Open('SELECT GRU_CODIGO, GRU_NOME FROM GRUPOS');
  aJson := TJSONArray.Create;
  Query.DataSet.First;
  while not Query.DataSet.Eof do
  begin
    oJson     := TJSONObject.Create;
    oJson.AddPair('codigo', TJSONNumber.Create(Query.DataSet.FieldByName('GRU_CODIGO').AsInteger));
    oJson.AddPair('nome', Query.DataSet.FieldByName('GRU_NOME').AsString);
    aJson.AddElement(oJson);
    Query.DataSet.Next;
  end;
  Res.Send<TJSONArray>(aJson);
end;

class procedure TProdutosController.GetFotoCategoria(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Query    : iQuery;
  Categoria: integer;
  oJson    : TJSONObject;
  imgBase64: string;
begin
  if Req.Params.Count > 0 then
  begin
    Categoria := Req.Params.Items['codigo'].ToInteger();
    Query := TDatabase.Query;
    Query.Clear;
    Query.Add('SELECT GRU_CAMINHO_IMAGEM FROM GRUPOS WHERE GRU_CODIGO = :CODIGO');
    Query.AddParam('CODIGO', Categoria);
    Query.Open();
    if not Query.DataSet.IsEmpty then
    begin
      oJson     := TJSONObject.Create;
      if FileExists(Query.DataSet.FieldByName('GRU_CAMINHO_IMAGEM').AsString) then
      begin
        imgBase64 := ConvertFileToBase64(Query.DataSet.FieldByName('GRU_CAMINHO_IMAGEM').AsString);
        oJson.AddPair('base64', imgBase64);
      end;
      oJson.AddPair('url', Query.DataSet.FieldByName('GRU_CAMINHO_IMAGEM').AsString);      
      Res.Send<TJSONObject>(oJson);
    end;
  end else
    Res.Send<TJSONObject>(TJSONObject.Create.AddPair('error', 'Categoria não informada')).Status(THTTPStatus.BadRequest);
end;

class procedure TProdutosController.GetFotoProduto(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Query    : iQuery;
  Codigo: integer;
  oJson    : TJSONObject;
  imgBase64: string;
begin
  Query := TDatabase.Query;
  Query.Clear;
  if Req.Params.Count > 0 then
  begin
    Codigo := Req.Params.Items['codigo'].ToInteger;
    Query.Add('SELECT PRO_CAMINHO_IMAGEM FROM PRODUTOS WHERE PRO_CODIGO = :CODIGO');
    Query.AddParam('CODIGO', Codigo);
    Query.Open;
    Query.DataSet.First;
    if not Query.DataSet.IsEmpty then
    begin
      oJson     := TJSONObject.Create;
      oJson.AddPair('url', Query.DataSet.FieldByName('PRO_CAMINHO_IMAGEM').AsString);
      if FileExists(Query.DataSet.FieldByName('PRO_CAMINHO_IMAGEM').AsString) then
      begin
        imgBase64 := ConvertFileToBase64(Query.DataSet.FieldByName('PRO_CAMINHO_IMAGEM').AsString);
        oJson.AddPair('base64', imgBase64);
      end;
      Res.Send<TJSONObject>(oJson);
    end;
  end else
    Res.Send<TJSONObject>(TJSONObject.Create.AddPair('error', 'Codigo do produto não informado')).Status(THTTPStatus.BadRequest);
end;

class procedure TProdutosController.GetGradeProduto(Req: THorseRequest;
  Res: THorseResponse; Next: TProc);
var
  Query: iQuery;
  Produto: Integer;
  oJson: TJSONObject;
  Tamanho: string;
begin
  if not Req.Params.ContainsKey('codigo') then
    raise Exception.Create('Codigo do Produto requerido');
  Produto := Req.Params.Items['codigo'].ToInteger;
  if not Req.Params.ContainsKey('tamanho') then
    raise Exception.Create('Tamanho do Produto requerido');
  Tamanho := Req.Params.Items['tamanho'];
  Query := TDatabase.Query;
  Query.Clear;
  Query.Add('SELECT GRA_CODIGO, GRA_VALOR, TAM_SIGLA FROM');
  Query.Add('GRADES JOIN TAMANHOS ON GRA_TAM = TAM_CODIGO');
  Query.Add('WHERE GRA_PRO = :PRODUTO AND TAM_SIGLA = :TAMANHO');
  Query.AddParam('PRODUTO', Produto);
  Query.AddParam('TAMANHO', Tamanho);
  Query.Open;
  if not Query.DataSet.IsEmpty then
  begin
    oJson := TJSONObject.Create;
    oJson.AddPair('codigo', TJSONNumber.Create(Query.DataSet.FieldByName('GRA_CODIGO').AsInteger));
    oJson.AddPair('valor', TJSONNumber.Create(Query.DataSet.FieldByName('GRA_VALOR').AsCurrency));
    oJson.AddPair('tamanho', Query.DataSet.FieldByName('TAM_SIGLA').AsString);
  end;
  Res.Send<TJSONObject>(oJson);
end;

class procedure TProdutosController.GetGradesProduto(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Query: iQuery;
  Produto: Integer;
  aJson: TJSONArray;
  oJson: TJSONObject;
begin
  if Req.Params.Count = 0 then
    raise Exception.Create('Codigo do Produto requerido');
  Produto := Req.Params.Items['codigo'].ToInteger;
  Query := TDatabase.Query;
  Query.Clear;
  Query.Add('SELECT GRA_CODIGO, GRA_VALOR, TAM_SIGLA FROM');
  Query.Add('GRADES JOIN TAMANHOS ON GRA_TAM = TAM_CODIGO');
  Query.Add('WHERE GRA_PRO = :PRODUTO');
  Query.AddParam('PRODUTO', Produto);
  Query.Open;
  aJson := TJSONArray.Create;
  Query.DataSet.First;
  while not Query.DataSet.Eof do
  begin
    oJson := TJSONObject.Create;
    oJson.AddPair('codigo', TJSONNumber.Create(Query.DataSet.FieldByName('GRA_CODIGO').AsInteger));
    oJson.AddPair('valor', TJSONNumber.Create(Query.DataSet.FieldByName('GRA_VALOR').AsCurrency));
    oJson.AddPair('tamanho', Query.DataSet.FieldByName('TAM_SIGLA').AsString);
    aJson.AddElement(oJson);
    Query.DataSet.Next;
  end;
  Res.Send<TJSONArray>(aJson);
end;

class procedure TProdutosController.GetProdutoPorCodigo(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Query    : iQuery;
  Codigo: integer;
  oJson    : TJSONObject;
  CodPro: Integer;
begin
  if not TryStrToInt(Req.Params.Items['codigo'], Codigo) then
  begin
    Res.Send<TJSONObject>(TJSONObject.Create.AddPair('message', 'Codigo invalido')).Status(THTTPStatus.BadRequest);
    Exit;
  end;
  Query := TDatabase.Query;
  Query.Clear;
  Query.Add('SELECT P.PRO_CODIGO, P.PRO_NOME, P.PRO_CODBARRA, P.PRO_VALORV, P.PRO_GRU,');
  Query.Add('       COALESCE(P.PRO_VALORC, 0) PRO_VALORC, COALESCE(P.PRO_VALORCM, 0) PRO_VALORCM,');
  Query.Add('       COALESCE(P.PRO_TIPO, '''') PRO_TIPO, COALESCE(P.PRO_EMBALAGEM, '''') PRO_EMBALAGEM,');
  Query.Add('       COALESCE(G.GRU_G1, 0) GRU_G1, COALESCE(G1.G1_NOME, '''') G1_NOME,');
  Query.Add('       (SELECT FIRST 1 GRA_CODIGO FROM GRADES WHERE GRA_PRO = P.PRO_CODIGO) GRA_CODIGO');
  Query.Add('FROM PRODUTOS P LEFT JOIN GRUPOS G ON P.PRO_GRU = G.GRU_CODIGO LEFT JOIN GRUPO_1 G1 ON G1.G1_CODIGO = G.GRU_G1');
  Query.Add('WHERE P.PRO_CODIGO = :CODIGO');
  Query.AddParam('CODIGO', Codigo);
  Query.Open;
  if not Query.DataSet.IsEmpty then
  begin
  	CodPro := Query.DataSet.FieldByName('PRO_CODIGO').AsInteger;
    oJson     := TJSONObject.Create;
    oJson.AddPair('codigo', TJSONNumber.Create(CodPro));
    oJson.AddPair('nome', Query.DataSet.FieldByName('PRO_NOME').AsString);
    oJson.AddPair('codbarra', Query.DataSet.FieldByName('PRO_CODBARRA').AsString);
    oJson.AddPair('valor', TJSONNumber.Create(Query.DataSet.FieldByName('PRO_VALORV').AsCurrency));
    oJson.AddPair('valorc', TJSONNumber.Create(Query.DataSet.FieldByName('PRO_VALORC').AsFloat));
    oJson.AddPair('valorcm', TJSONNumber.Create(Query.DataSet.FieldByName('PRO_VALORCM').AsFloat));
    oJson.AddPair('tipo', TProducaoService.NormalizarTipoProduto(Query.DataSet.FieldByName('PRO_TIPO').AsString));
    oJson.AddPair('unidade', TProducaoService.NormalizarUnidade(Query.DataSet.FieldByName('PRO_EMBALAGEM').AsString));
    oJson.AddPair('categoria', TJSONNumber.Create(Query.DataSet.FieldByName('PRO_GRU').AsInteger));
    oJson.AddPair('grade', TJSONNumber.Create(Query.DataSet.FieldByName('GRA_CODIGO').AsInteger));
    oJson.AddPair('grupo', TJSONNumber.Create(Query.DataSet.FieldByName('GRU_G1').AsInteger));    
    oJson.AddPair('g1_nome', Query.DataSet.FieldByName('G1_NOME').AsString);
    Res.Send<TJSONObject>(oJson);
  end else
    Res.Send<TJSONObject>(TJSONObject.Create.AddPair('message', 'Produto not found')).Status(THTTPStatus.BadRequest);
end;

class procedure TProdutosController.GetNiveisProduto(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Codigo: integer;
  aJson: TJSONArray;
begin  
  Codigo := Req.Params.Items['codigo'].ToInteger;
  aJson := TJSONArray.Create;
  aJson := BuscaNiveisProduto(Codigo);
  if aJson.Count > 0 then
  begin
  	Res.Send<TJSONArray>(aJson);
  end else
    Res.Send<TJSONObject>(TJSONObject.Create.AddPair('message', 'Niveis not found')).Status(THTTPStatus.BadRequest);
end;

class function TProdutosController.BuscaNiveisProduto(CodPro: Integer): TJSONArray;
var
  Query: iQuery;
  Nivel: TNivel;
begin
  Result := TJSONArray.Create;

  Query := TDatabase.Query;
  Query.Add('SELECT NI_CODIGO, NI_TITULO, NI_PRO, NI_DESCRICAO, NI_SELECAO_MIN, NI_SELECAO_MAX ');
  Query.Add('FROM NIVEIS ');
  Query.Add('WHERE NI_PRO = :PRO ');
  Query.Add('ORDER BY NI_CODIGO');
  Query.AddParam('PRO', CodPro);
  Query.Open();

  while not Query.DataSet.Eof do
  begin
    // Instancia o objeto sem passar pelo SetCodigo lento
    Nivel := TNivel.Create;
    try
      // Atribuição direta dos campos já carregados na Query
      Nivel.Codigo     := Query.DataSet.FieldByName('NI_CODIGO').AsInteger;
      Nivel.Titulo      := Query.DataSet.FieldByName('NI_TITULO').AsString;
      Nivel.CodProduto  := Query.DataSet.FieldByName('NI_PRO').AsInteger;
      Nivel.Descricao   := Query.DataSet.FieldByName('NI_DESCRICAO').AsString;
      Nivel.SelecaoMin  := Query.DataSet.FieldByName('NI_SELECAO_MIN').AsInteger;
      Nivel.SelecaoMax  := Query.DataSet.FieldByName('NI_SELECAO_MAX').AsInteger;
      // Adiciona o JSON do objeto no Array do resultado
      // (Assumindo que sua classe base TTabela ou TNivel tenha ToJsonObject)
      Result.AddElement(Nivel.ToJsonObject); 
    finally
      Nivel.Free; // ou DisposeOf se estiver usando ARC em versoes antigas
    end;
    Query.DataSet.Next;
  end;
end;

class procedure TProdutosController.GetProdutosPorGrupo(Req: THorseRequest; Res: THorseResponse);
var
	Produto      : TProdutos;
	Query        : iQuery;
	ListaProdutos: TJSONArray;
	CodGrupo : Integer;
	Limite       : Integer;
	Pagina       : Integer;
	Pular        : Integer;
	SQL          : string;
begin
	if not Req.Params.ContainsKey('id') then
		raise Exception.Create('Id do grupo nao informado!');
	CodGrupo  := Req.Params.Items['id'].ToInteger();
	ListaProdutos := TJSONArray.Create;
	Query         := TDatabase.Query;
	
	// Obtem parametros de paginacao (page e limit)
	Limite := 10; // Valor padrao
	Pagina := 1;  // Valor padrao (primeira pagina)
	
	if Req.Query.ContainsKey('limit') then
		Limite := Req.Query.Items['limit'].ToInteger();
	if Req.Query.ContainsKey('page') then
		Pagina := Req.Query.Items['page'].ToInteger();
	
	// Calcula o SKIP baseado na pagina e limite
	// Formula: SKIP = (Pagina - 1) * Limite
	if Pagina < 1 then
		Pagina := 1;
	Pular := (Pagina - 1) * Limite;
	
	// Monta SQL com paginacao usando FIRST e SKIP do Firebird
	Query.Clear;
	if Limite > 0 then
		SQL := Format(
      'SELECT FIRST %d SKIP %d PRO_CODIGO FROM PRODUTOS ' +
      'WHERE PRO_GRU = :GRUPO AND COALESCE(PRO_ESTADO, ''ATIVO'') = ''ATIVO'' ' +
      '  AND COALESCE(NULLIF(UPPER(TRIM(PRO_TIPO)), ''''), ''REVENDA'') NOT IN (''MP'', ''MATERIA_PRIMA'', ''MATERIA-PRIMA'') ' +
      'ORDER BY PRO_CODIGO', [Limite, Pular])
	else
		SQL :=
      'SELECT PRO_CODIGO FROM PRODUTOS ' +
      'WHERE PRO_GRU = :GRUPO AND COALESCE(PRO_ESTADO, ''ATIVO'') = ''ATIVO'' ' +
      '  AND COALESCE(NULLIF(UPPER(TRIM(PRO_TIPO)), ''''), ''REVENDA'') NOT IN (''MP'', ''MATERIA_PRIMA'', ''MATERIA-PRIMA'') ' +
      'ORDER BY PRO_CODIGO';
	
	Query.Add(SQL);
	Query.AddParam('GRUPO', CodGrupo);
	Query.Open();
	Query.Dataset.First;
	while not Query.Dataset.Eof do
	begin
		Produto := TProdutos.Create(TDatabase.Connection);
		Produto.BuscaDadosTabela(Query.Dataset.FieldByName('PRO_CODIGO').AsInteger);
		ListaProdutos.Add(Produto.ToJsonObject);
		Query.Dataset.Next;
	end;
	Res.Send<TJSONArray>(ListaProdutos);
end;

class procedure TProdutosController.Registrar;
begin
  THorse.Get('/v1/produtos', Get);
  THorse.Get('/v1/produtos/:codigo', GetProdutoPorCodigo);
  THorse.Get('/v1/produtos/:codigo/niveis', GetNiveisProduto);
  THorse.Get('/v1/categorias', GetCategorias);
  THorse.Get('/v1/categorias/:codigo/foto', GetFotoCategoria);
  THorse.Get('/v1/produtos/:codigo/foto', GetFotoProduto);
  THorse.Get('/v1/produtos/grades/:codigo', GetGradesProduto);
  THorse.Get('/v1/produtos/grades/:codigo/:tamanho', GetGradeProduto);
  THorse.Get('/v1/categorias/produtos/:id', GetProdutosPorGrupo);
  ///
  THorse.Get('/Produtos', Get);
  THorse.Get('/Produtos/:codigo', GetProdutoPorCodigo);
  THorse.Get('/Produtos/:codigo/niveis', GetNiveisProduto);
  THorse.Get('/Categorias', GetCategorias);
  THorse.Get('/Categorias/:codigo/foto', GetFotoCategoria);
  THorse.Get('/Produtos/:codigo/foto', GetFotoProduto);
  THorse.Get('/Produtos/grades/:codigo', GetGradesProduto);
  THorse.Get('/Produtos/grades/:codigo/:tamanho', GetGradeProduto);
  THorse.Get('/Categorias/produtos/:id', GetProdutosPorGrupo);
end;

initialization
  Swagger
    // Lista produtos
    .Path('produtos')
      .Tag('produtos')
      .GET('Lista Produtos', 'Lista produtos por filtros')
        .AddResponse(200, 'Operação bem sucedida')
          .Schema(TProdutos)
          .IsArray(True)
        .&End
        .AddResponse(400).&End
        .AddResponse(500).&End
      .&End
    .&End

    // Produto por codigo
    .Path('produtos/{codigo}')
      .Tag('produtos')
      .GET('Obtem Produto por codigo', 'Retorna produto por codigo')
        .AddParamPath('codigo', 'Codigo do produto').Required(True).Schema(SWAG_INTEGER).&End
        .AddResponse(200).&End
        .AddResponse(400).&End
        .AddResponse(500).&End
      .&End
    .&End

    // Niveis/grades do produto
    .Path('produtos/{codigo}/niveis')
      .Tag('produtos')
      .GET('Obtem niveis do produto', 'Retorna grades/niveis do produto')
        .AddParamPath('codigo', 'Codigo do produto').Required(True).Schema(SWAG_INTEGER).&End
        .AddResponse(200).&End
      .&End
    .&End

    // Categorias
    .Path('categorias')
      .Tag('produtos')
      .GET('Categorias', 'Lista categorias')
        .AddResponse(200).&End
      .&End
    .&End

    // Foto da categoria
    .Path('categorias/{codigo}/foto')
      .Tag('produtos')
      .GET('Foto da categoria', 'Retorna foto da categoria')
        .AddParamPath('codigo', 'Codigo da categoria').Required(True).Schema(SWAG_INTEGER).&End
        .AddResponse(200).&End
      .&End
    .&End

    // Foto do produto
    .Path('produtos/{codigo}/foto')
      .Tag('produtos')
      .GET('Foto do produto', 'Retorna foto do produto')
        .AddParamPath('codigo', 'Codigo do produto').Required(True).Schema(SWAG_INTEGER).&End
        .AddResponse(200).&End
      .&End
    .&End

    // Grades do produto
    .Path('produtos/grades/{codigo}')
      .Tag('produtos')
      .GET('Grades do produto', 'Retorna grades do produto')
        .AddParamPath('codigo', 'Codigo do produto').Required(True).Schema(SWAG_INTEGER).&End
        .AddResponse(200).&End
      .&End
    .&End

    // Grade por tamanho
    .Path('produtos/grades/{codigo}/{tamanho}')
      .Tag('produtos')
      .GET('Grade por tamanho', 'Retorna grade do produto por tamanho')
        .AddParamPath('codigo', 'Codigo do produto').Required(True).Schema(SWAG_INTEGER).&End
        .AddParamPath('tamanho', 'Sigla do tamanho').Required(True).Schema(SWAG_STRING).&End
        .AddResponse(200).&End
      .&End
    .&End

  .&End

end.
