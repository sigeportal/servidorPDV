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
  end;

implementation

{ TProdutosController }

uses 
	UnitFuncoesComuns, 
  UnitTabela.Helpers,
  UnitDatabase,
  UnitProdutos.Model, UnitGrades.Model;

class procedure TProdutosController.Get(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Query    : iQuery;
  Categoria: integer;
  Busca: string;
  aJson    : TJSONArray;
  oJson    : TJSONObject;
  grupo: Integer;
  Grades: TGrades;
begin
	Grades := TGrades.Create(TDatabase.Connection);
  try
    Grades.CriaTabela;
  finally
    Grades.DisposeOf;
  end;
  Query := TDatabase.Query;
  aJson := TJSONArray.Create;
  Query.Clear;
  Busca := Trim(Req.Query.Items['busca']);

  Query.Add('SELECT PRO_CODIGO, PRO_NOME, PRO_CODBARRA, PRO_VALORV, GRU_CODIGO, GRU_G1, G1_NOME,');
  Query.Add('(SELECT FIRST 1 GRA_CODIGO FROM GRADES WHERE GRA_PRO = PRO_CODIGO) GRA_CODIGO');
  Query.Add('FROM PRODUTOS JOIN GRUPOS ON PRO_GRU = GRU_CODIGO JOIN GRUPO_1 ON G1_CODIGO = GRU_G1');
  Query.Add('WHERE PRO_ESTADO = ''ATIVO''');

  if Req.Query.Count > 0 then
  begin
    if Req.Query.ContainsKey('categoria') then
    begin
      Categoria := Req.Query.Items['categoria'].ToInteger;
      Query.Add('AND GRU_CODIGO = :SUBGRUPO');
      Query.AddParam('SUBGRUPO', Categoria);
    end;
    if Req.Query.ContainsKey('grupo') then
    begin
      grupo := Req.Query.Items['grupo'].ToInteger;
      Query.Add('AND GRU_G1 = :GRUPO');
      Query.AddParam('GRUPO', grupo);
    end;
  end;

  if Busca <> '' then
  begin
    Query.Add('AND (UPPER(PRO_NOME) LIKE :BUSCA OR CAST(PRO_CODIGO AS VARCHAR(20)) LIKE :BUSCA OR UPPER(PRO_CODBARRA) LIKE :BUSCA)');
    Query.AddParam('BUSCA', '%' + UpperCase(Busca) + '%');
  end;

  Query.Add('ORDER BY PRO_NOME');
  Query.Open();
  Query.DataSet.First;
  while not Query.DataSet.Eof do
  begin
    oJson     := TJSONObject.Create;
    oJson.AddPair('codigo', TJSONNumber.Create(Query.DataSet.FieldByName('PRO_CODIGO').AsInteger));
    oJson.AddPair('nome', Query.DataSet.FieldByName('PRO_NOME').AsString);
    oJson.AddPair('codbarra', Query.DataSet.FieldByName('PRO_CODBARRA').AsString);
    oJson.AddPair('valor', TJSONNumber.Create(Query.DataSet.FieldByName('PRO_VALORV').AsCurrency));
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
      imgBase64 := ConvertFileToBase64(Query.DataSet.FieldByName('GRU_CAMINHO_IMAGEM').AsString);
      oJson.AddPair('base64', imgBase64);
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
//      imgBase64 := ConvertFileToBase64(Query.DataSet.FieldByName('PRO_CAMINHO_IMAGEM').AsString);
      oJson     := TJSONObject.Create;
      oJson.AddPair('url', Query.DataSet.FieldByName('PRO_CAMINHO_IMAGEM').AsString);
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
  Query := TDatabase.Query;
  Query.Clear;
  Codigo := Req.Params.Items['codigo'].ToInteger;
  Query.Add('SELECT PRO_CODIGO, PRO_NOME, PRO_CODBARRA, PRO_VALORV, PRO_GRU, GRU_G1, G1_NOME,');
  Query.Add('(SELECT FIRST 1 GRA_CODIGO FROM GRADES WHERE GRA_PRO = PRO_CODIGO) GRA_CODIGO');
  Query.Add('FROM PRODUTOS JOIN GRUPOS ON PRO_GRU = GRU_CODIGO JOIN GRUPO_1 ON G1_CODIGO = GRU_G1');
  Query.Add('AND PRO_CODIGO = :CODIGO');
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

class function TProdutosController.BuscaNiveisProduto(CodPro: integer): TJsonArray;
var
	Niveis: TNivel;
  ListaNiveis: TList<TNivel>;
  i: Integer;
begin
	//cria objetos
  Niveis := TNivel.Create(TDatabase.Connection);
  Niveis.CriaTabela;
  //
	Result := TJSONArray.Create;
	//busca niveis por produto
  ListaNiveis := Niveis.PreencheListaWhere<TNivel>('NI_PRO='+CodPro.ToString, 'NI_CODIGO');
  for i := 0 to Pred(ListaNiveis.Count) do
	  Result.AddElement(ListaNiveis[i].ToJsonObject); 
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
