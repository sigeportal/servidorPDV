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
    class procedure GetCredito(Req: THorseRequest; Res: THorseResponse);
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

class procedure TClientesController.GetCredito(Req: THorseRequest; Res: THorseResponse);
var
  QueryCli, QueryRec: iQuery;
  Id: Integer;
  Nome: string;
  Limite, TotalAberto, SaldoDisponivel: Currency;
  DataObj, TituloObj: TJSONObject;
  TitulosArr: TJSONArray;
begin
  if not TryStrToInt(Req.Params.Items['id'], Id) then
  begin
    Res.Status(THTTPStatus.BadRequest)
      .Send<TJSONObject>(TJSONObject.Create.AddPair('error', 'ID do cliente invalido'));
    Exit;
  end;

  QueryCli := TDatabase.Query;
  QueryRec := TDatabase.Query;
  DataObj := TJSONObject.Create;
  TitulosArr := TJSONArray.Create;
  try
    QueryCli.Clear;
    QueryCli.Add('SELECT CLI_CODIGO, CLI_NOME, COALESCE(CLI_LIMITE, 0) CLI_LIMITE FROM CLIENTES WHERE CLI_CODIGO = :CLI');
    QueryCli.AddParam('CLI', Id);
    QueryCli.Open;

    if QueryCli.DataSet.IsEmpty then
    begin
      DataObj.Free;
      TitulosArr.Free;
      Res.Status(THTTPStatus.NotFound)
        .Send<TJSONObject>(TJSONObject.Create.AddPair('error', 'Cliente nao encontrado'));
      Exit;
    end;

    Nome := QueryCli.DataSet.FieldByName('CLI_NOME').AsString;
    Limite := QueryCli.DataSet.FieldByName('CLI_LIMITE').AsCurrency;

    QueryRec.Clear;
    QueryRec.Add('SELECT R.REC_CODIGO, V.VEN_CODIGO, R.REC_DUPLICATA, V.VEN_DATA, R.REC_VENCIMENTO,');
    QueryRec.Add('       (R.REC_VALOR + COALESCE(R.REC_JUROS, 0) - COALESCE(R.REC_DESCONTOS, 0)) VLR_ABERTO,');
    QueryRec.Add('       COALESCE(R.REC_TIPO, '''') REC_TIPO');
    QueryRec.Add('FROM VENDAS V');
    QueryRec.Add('JOIN RECEBIMENTOS R ON V.VEN_FAT = R.REC_FAT');
    QueryRec.Add('WHERE V.VEN_CLI = :CLI');
    QueryRec.Add('  AND R.REC_ESTADO = 1');
    QueryRec.Add('  AND (R.REC_SITUACAO >= 0 AND R.REC_SITUACAO < 2)');
    QueryRec.Add('  AND V.VEN_DATAC = ''01/01/1900''');
    QueryRec.Add('ORDER BY R.REC_VENCIMENTO ASC');
    QueryRec.AddParam('CLI', Id);
    QueryRec.Open;

    TotalAberto := 0;
    QueryRec.DataSet.First;
    while not QueryRec.DataSet.Eof do
    begin
      TotalAberto := TotalAberto + QueryRec.DataSet.FieldByName('VLR_ABERTO').AsCurrency;

      TituloObj := TJSONObject.Create;
      TituloObj.AddPair('codigo', TJSONNumber.Create(QueryRec.DataSet.FieldByName('REC_CODIGO').AsInteger));
      TituloObj.AddPair('venda', TJSONNumber.Create(QueryRec.DataSet.FieldByName('VEN_CODIGO').AsInteger));
      TituloObj.AddPair('duplicata', QueryRec.DataSet.FieldByName('REC_DUPLICATA').AsString);
      TituloObj.AddPair('emissao', FormatDateTime('yyyy-mm-dd', QueryRec.DataSet.FieldByName('VEN_DATA').AsDateTime));
      TituloObj.AddPair('vencimento', FormatDateTime('yyyy-mm-dd', QueryRec.DataSet.FieldByName('REC_VENCIMENTO').AsDateTime));
      TituloObj.AddPair('valor', TJSONNumber.Create(QueryRec.DataSet.FieldByName('VLR_ABERTO').AsCurrency));
      TituloObj.AddPair('tipo', QueryRec.DataSet.FieldByName('REC_TIPO').AsString);
      TitulosArr.AddElement(TituloObj);

      QueryRec.DataSet.Next;
    end;

    SaldoDisponivel := Limite - TotalAberto;

    DataObj.AddPair('codigo', TJSONNumber.Create(Id));
    DataObj.AddPair('nome', Nome);
    DataObj.AddPair('limite', TJSONNumber.Create(Limite));
    DataObj.AddPair('total_aberto', TJSONNumber.Create(TotalAberto));
    DataObj.AddPair('saldo_disponivel', TJSONNumber.Create(SaldoDisponivel));
    DataObj.AddPair('titulos_abertos', TitulosArr);

    Res.Send<TJSONObject>(DataObj);
  finally
    QueryCli := nil;
    QueryRec := nil;
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
        .Group
        .Prefix('/v1')
        .Route('/clientes/:id/credito')
          .Get(GetCredito)
        .&End;
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
  .BasePath('v1')
    .Path('clientes/{id}/credito')
      .Tag('Clientes')
      .GET('Consulta limite e saldo a receber do cliente')
        .AddParamPath('id', 'Id do cliente para consultar credito')
          .Required(True)
          .Schema(SWAG_INTEGER)
        .&End
        .AddResponse(200, 'Operacao bem sucedida').&End
        .AddResponse(404, 'Cliente nao encontrado').&End
        .AddResponse(500).&End
      .&End
    .&End
  .&End

end.
