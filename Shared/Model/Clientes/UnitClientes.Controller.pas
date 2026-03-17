unit UnitClientes.Controller;

interface
uses
  Horse,
  Horse.Commons,
  Horse.GBSwagger,
  Classes,
  SysUtils,
  System.Json;

type
  TClientesController = class
    class procedure Router;
    class procedure Get(Req: THorseRequest; Res: THorseResponse);
    class procedure GetForID(Req: THorseRequest; Res: THorseResponse);
    class procedure Post(Req: THorseRequest; Res: THorseResponse);
    class procedure Put(Req: THorseRequest; Res: THorseResponse);
    class procedure Delete(Req: THorseRequest; Res: THorseResponse);
  end;

implementation

{ TClientesController }

uses
  UnitConnection.Model.Interfaces,
  UnitDatabase,
  UnitFunctions,
  UnitClientes.Model,
  UnitConstants,
  UnitTabela.Helpers;

class procedure TClientesController.Delete(Req: THorseRequest; Res: THorseResponse);
var Clientes: TClientes;
  id: Integer;
begin
  try
    id := Req.Params.Items['id'].ToInteger();
    Clientes := TClientes.Create(TDatabase.Connection);
    Clientes.Apagar(id);
    Res.Send('').Status(THTTPStatus.NoContent);
  finally
    Clientes.DisposeOf;
  end;
end;

class procedure TClientesController.Get(Req: THorseRequest; Res: THorseResponse);
var
  Clientes: TClientes;
  aJson: TJSONArray;
  Query: iQuery;
  Filtros: TStringList;
  ParamName, ParamValue, QueryParams: string;
  i: Integer;
  Limite: Integer;
  Pagina: Integer;
  Pular: Integer;
  SQLBase: string;
  WhereClause: string;
begin
  aJson := TJSONArray.Create;
  Query := TDatabase.Query;
  Clientes := TClientes.Create(TDatabase.Connection);
  Clientes.CriaTabela;
  Filtros := TStringList.Create;
  try
    // Obtem parametros de paginacao (page e limit)
    Limite := 10; // Valor padrao
    Pagina := 1;  // Valor padrao (primeira pagina)
    
    if Req.Query.ContainsKey('limit') then
      Limite := Req.Query.Items['limit'].ToInteger();
    if Req.Query.ContainsKey('page') then
      Pagina := Req.Query.Items['page'].ToInteger();
    
    // Calcula o SKIP baseado na pagina e limite
    if Pagina < 1 then
      Pagina := 1;
    Pular := (Pagina - 1) * Limite;
    
    // Monta SELECT com paginacao
    if Limite > 0 then
      SQLBase := Format('SELECT FIRST %d SKIP %d DISTINCT CLI_CODIGO FROM CLIENTES', [Limite, Pular])
    else
      SQLBase := 'SELECT DISTINCT CLI_CODIGO FROM CLIENTES';

    // Monta filtros dinamicos
    for QueryParams in Req.Query.Dictionary.Keys do
    begin
    	ParamName := QueryParams.ToUpper;
      ParamValue := Req.Query.Items[ParamName].Replace('''', '');

      // Ignora par metros de controle
      if (ParamName = 'LIMIT') or (ParamName = 'PAGE') then
        Continue;

      // Adiciona filtro com LIKE para texto
      if not ParamValue.IsEmpty then
        Filtros.Add(Format('%s LIKE %s', [ParamName, QuotedStr('%' + ParamValue + '%')]));
    end;

    // Monta SQL final
    Query.Add(SQLBase);
    if Filtros.Count > 0 then
    begin
      WhereClause := 'WHERE ' + String.Join(' OR ', Filtros.ToStringArray);
      Query.Add(WhereClause);
    end;
    Query.Add('ORDER BY CLI_CODIGO');
    Query.Open;

    // Monta JSON de retorno
    Query.Dataset.First;
    while not Query.Dataset.Eof do
    begin
      Clientes.BuscaDadosTabela(Query.Dataset.FieldByName('CLI_CODIGO').AsInteger);
      aJson.Add(TJSONObject.ParseJSONValue(Clientes.ToJson) as TJSONObject);
      Query.Dataset.Next;
    end;

    Res.Send<TJSONArray>(aJson);
  finally
    Filtros.Free;
    Clientes.DisposeOf;
  end;
end;

class procedure TClientesController.GetForID(Req: THorseRequest; Res: THorseResponse);
var Clientes: TClientes;
    aJson: TJSONArray;
    id: Integer;
begin
  aJson := TJSONArray.Create;
  id := Req.Params.Items['id'].ToInteger();
  try
    Clientes := TClientes.Create(TDatabase.Connection);
    Clientes.CriaTabela;
    Clientes.BuscaDadosTabela(id);
    Res.Send<TJSONObject>(Clientes.ToJsonObject);
  finally
    Clientes.DisposeOf;
  end;
end;

class procedure TClientesController.Post(Req: THorseRequest; Res: THorseResponse);
var Clientes: TClientes;
begin
  try
    Clientes := TClientes.Create(TDatabase.Connection).fromJson<TClientes>(Req.Body);
    Clientes.CriaTabela;
    if Clientes.Codigo = 0 then
        Clientes.Codigo := GeraCodigo('CLIENTES', 'CLI_CODIGO');
    Clientes.SalvaNoBanco(1);
    Res.Send<TJSONObject>(Clientes.ToJsonObject);
  finally
    Clientes.DisposeOf;
  end;
end;

class procedure TClientesController.Put(Req: THorseRequest; Res: THorseResponse);
var Clientes: TClientes;
begin
  try
    Clientes := TClientes.Create(TDatabase.Connection).fromJson<TClientes>(Req.Body);
    Clientes.CriaTabela;
    Clientes.SalvaNoBanco(1);
    Res.Send<TJSONObject>(Clientes.ToJsonObject);
  finally
    Clientes.DisposeOf;
  end;
end;

class procedure TClientesController.Router;
begin
  THorse.Group
        .Prefix('/v1')
        .Route('/clientes')
          .Get(Get)
          .Post(Post)
          .Put(Put)
        .&End
        .Group
        .Prefix('/v1')
        .Route('/clientes/:id')
          .Get(GetForID)
          .Delete(Delete)
        .&End
end;

initialization
    Swagger
	.BasePath('v1')
    .Path('clientes')
      .Tag('Clientes')
      .GET('Lista Todos(as)', 'Lista todos(as) os(as) Clientess')
        .AddResponse(200, 'Operação bem Sucedida')
          .Schema(TClientes)
          .IsArray(True)
        .&End
        .AddResponse(400).&End
        .AddResponse(500).&End
      .&End
      .POST('Criar Clientes', 'Cria um(a) novo(a) Clientes')
        .AddParamBody('Dados do(a) Clientes', 'Clientes')
          .Required(True)
          .Schema(TClientes)
        .&End
        .AddResponse(201, 'Created')
          .Schema(TClientes)
        .&End
        .AddResponse(400, 'BadRequest')
          .Schema(TAPIError)
        .&End
        .AddResponse(500).&End
      .&End
      .PUT('Atualiza Clientes', 'Atualiza os dados de um(a) Clientes')
        .AddParamBody('Dados do(a) Clientes', 'Clientes')
          .Required(True)
          .Schema(TClientes)
        .&End
        .AddResponse(200, 'Ok')
          .Schema(TClientes)
        .&End
        .AddResponse(400, 'BadRequest')
          .Schema(TAPIError)
        .&End
        .AddResponse(500).&End
      .&End
    .&End
  .&End
  .BasePath('v1')
    .Path('clientes/{id}')
      .Tag('Clientes')
      .GET('Obtem um(a) Clientes')
        .AddParamPath('id', 'Id do(a) Clientes para buscar')
          .Required(True)
          .Schema(SWAG_INTEGER)
        .&End
        .AddResponse(200, 'Operação bem Sucedida')
          .Schema(TClientes)
        .&End
        .AddResponse(404, 'Clientes não encontrado(a)').&End
        .AddResponse(400, 'BadRequest')
          .Schema(TAPIError)
        .&End
        .AddResponse(500).&End
      .&End
      .DELETE('Apagar um(a) Clientes')
        .AddParamPath('id', 'id do(a) Clientes para deletar')
          .Required(True)
          .Schema(SWAG_INTEGER)
        .&End
        .AddResponse(404, 'Clientes não encontrado(a)').&End
        .AddResponse(400, 'BadRequest')
          .Schema(TAPIError)
        .&End
        .AddResponse(500).&End
      .&End
    .&End
  .&End

end.
