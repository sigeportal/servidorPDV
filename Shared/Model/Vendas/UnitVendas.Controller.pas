unit UnitVendas.Controller;

interface
uses
  Horse,
  Horse.Commons,
  Horse.GBSwagger,
  Classes,
  SysUtils,
  System.Json, UnitVenEst.Model, UnitOperacoes.Strategy.Interfaces,
  UnitOperacao.Venda;

type
  TVendasController = class
    class procedure Router;
    class procedure Get(Req: THorseRequest; Res: THorseResponse);
    class procedure GetForID(Req: THorseRequest; Res: THorseResponse);
    class procedure Post(Req: THorseRequest; Res: THorseResponse);
    class procedure Put(Req: THorseRequest; Res: THorseResponse);
    class procedure Delete(Req: THorseRequest; Res: THorseResponse);
  end;

implementation

{ TVendasController }

uses
  UnitConnection.Model.Interfaces,
  UnitDatabase,
  UnitFunctions,
  UnitVendas.Model,
  UnitConstants,
  UnitTabela.Helpers, System.Generics.Collections;

class procedure TVendasController.Delete(Req: THorseRequest; Res: THorseResponse);
var Vendas: TVendas;
  id: Integer;
begin
  try
    id := Req.Params.Items['id'].ToInteger();
    Vendas := TVendas.Create(TDatabase.Connection);
    Vendas.Apagar(id);
    Res.Send('').Status(THTTPStatus.NoContent);
  finally
    Vendas.DisposeOf;
  end;
end;

class procedure TVendasController.Get(Req: THorseRequest; Res: THorseResponse);
var
  Vendas: TVendas;
  aJson: TJSONArray;
  Query: iQuery;
  Filtros: TStringList;
  ParamName, ParamValue, QueryParams: string;
  i: Integer;
  Total: Integer;
  SQLBase: string;
  WhereClause: string;
begin
  aJson := TJSONArray.Create;
  Query := TDatabase.Query;
  Vendas := TVendas.Create(TDatabase.Connection);
  Vendas.CriaTabela;
  Filtros := TStringList.Create;
  try
    // Monta SELECT com ou sem limite
    if Req.Query.ContainsKey('total') then
    begin
      Total := Req.Query.Items['total'].ToInteger();
      if Total > 0 then
        SQLBase := Format('SELECT FIRST %d DISTINCT VEN_CODIGO FROM VENDAS', [Total])
      else
        SQLBase := 'SELECT DISTINCT VEN_CODIGO FROM VENDAS';
    end
    else
      SQLBase := 'SELECT DISTINCT VEN_CODIGO FROM VENDAS';

    // Monta filtros dinâmicos
    for QueryParams in Req.Query.Dictionary.Keys do
    begin
    	ParamName := QueryParams.ToUpper;
      ParamValue := Req.Query.Items[ParamName].Replace('''', '');

      // Ignora parâmetros de controle como "total"
      if ParamName = 'TOTAL' then
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
    Query.Add('ORDER BY VEN_CODIGO');
    Query.Open;

    // Monta JSON de retorno
    Query.Dataset.First;
    while not Query.Dataset.Eof do
    begin
      Vendas.BuscaDadosTabela(Query.Dataset.FieldByName('VEN_CODIGO').AsInteger);
      aJson.Add(TJSONObject.ParseJSONValue(Vendas.ToJson) as TJSONObject);
      Query.Dataset.Next;
    end;

    Res.Send<TJSONArray>(aJson);
  finally
    Filtros.Free;
    Vendas.DisposeOf;
  end;
end;

class procedure TVendasController.GetForID(Req: THorseRequest; Res: THorseResponse);
var Vendas: TVendas;
    aJson: TJSONArray;
    id: Integer;
begin
  aJson := TJSONArray.Create;
  id := Req.Params.Items['id'].ToInteger();
  try
    Vendas := TVendas.Create(TDatabase.Connection);
    Vendas.CriaTabela;
    Vendas.BuscaDadosTabela(id);
    Res.Send<TJSONObject>(Vendas.ToJsonObject);
  finally
    Vendas.DisposeOf;
  end;
end;

class procedure TVendasController.Post(Req: THorseRequest; Res: THorseResponse);
var Vendas: TVendas;
  i: Integer;
  OperacaoVenda: iOperacoesStrategy;
begin
  Vendas := TVendas.Create(TDatabase.Connection);
//  Vendas.CriaTabela; 
  Vendas := Vendas.fromJson<TVendas>(Req.Body);
  OperacaoVenda := TOperacaoVenda.New;
  OperacaoVenda.SetOperacao(Vendas);
  //tratamento para os itens
  if Assigned(Vendas.Itens) then
  begin
    for i := Low(Vendas.Itens) to High(Vendas.Itens) do
    begin
      OperacaoVenda.SetItens(Vendas.Itens[i]);
    end;
  end;   
  //insere operacao Venda    
  OperacaoVenda.SetPed_Fat(Vendas.PedFat);
  for i := Low(Vendas.PedFat.PFParcelas) to High(Vendas.PedFat.PFParcelas) do
  begin
    OperacaoVenda.SetPF_Parcela(Vendas.PedFat.PFParcelas[i]);
  end;    
  OperacaoVenda.SetTipoFatura(TTipoFatura.Vista);
  OperacaoVenda.InsereOperacao;
  OperacaoVenda.InsereItens;
  OperacaoVenda.InserePedFat;
  OperacaoVenda.InserePFParcela;    
  OperacaoVenda.InsereFaturamento;
  ////
  Res.Send<TJSONObject>(Vendas.ToJsonObject);
end;

class procedure TVendasController.Put(Req: THorseRequest; Res: THorseResponse);
var Vendas: TVendas;
begin
  try
    Vendas := TVendas.Create(TDatabase.Connection).fromJson<TVendas>(Req.Body);
    Vendas.CriaTabela;
    Vendas.SalvaNoBanco(1);
    Res.Send<TJSONObject>(Vendas.ToJsonObject);
  finally
    Vendas.DisposeOf;
  end;
end;

class procedure TVendasController.Router;
begin
  THorse.Group
        .Prefix('/v1')
        .Route('/vendas')
          .Get(Get)
          .Post(Post)
          .Put(Put)
        .&End
        .Group
        .Prefix('/v1')
        .Route('/vendas/:id')
          .Get(GetForID)
          .Delete(Delete)
        .&End
end;

initialization
  Swagger
  .Path('vendas')
      .Tag('Vendas')
      .GET('Lista Todos(as)', 'Lista todos(as) os(as) Vendass')
        .AddResponse(200, 'Operação bem Sucedida')
          .Schema(TVendasResponse)
          .IsArray(True)
        .&End
        .AddResponse(400).&End
        .AddResponse(500).&End
      .&End
      .POST('Criar Vendas', 'Cria um(a) novo(a) Vendas')
        .AddParamBody('Dados do(a) Vendas', 'Vendas')
          .Required(True)
          .Schema(TVendasResponse)
        .&End
        .AddResponse(201, 'Created')
          .Schema(TVendasResponse)
        .&End
        .AddResponse(400, 'BadRequest')
          .Schema(TAPIError)
        .&End
        .AddResponse(500).&End
      .&End
      .PUT('Atualiza Vendas', 'Atualiza os dados de um(a) Vendas')
        .AddParamBody('Dados do(a) Vendas', 'Vendas')
          .Required(True)
          .Schema(TVendasResponse)
        .&End
        .AddResponse(200, 'Ok')
          .Schema(TVendasResponse)
        .&End
        .AddResponse(400, 'BadRequest')
          .Schema(TAPIError)
        .&End
        .AddResponse(500).&End
      .&End
    .&End
    .Path('vendas/{id}')
      .Tag('Vendas')
      .GET('Obtem um(a) Vendas')
        .AddParamPath('id', 'Id do(a) Vendas para buscar')
          .Required(True)
          .Schema(SWAG_INTEGER)
        .&End
        .AddResponse(200, 'Operação bem Sucedida')
          .Schema(TVendas)
        .&End
        .AddResponse(404, 'Vendas não encontrado(a)').&End
        .AddResponse(400, 'BadRequest')
          .Schema(TAPIError)
        .&End
        .AddResponse(500).&End
      .&End
      .DELETE('Apagar um(a) Vendas')
        .AddParamPath('id', 'id do(a) Vendas para deletar')
          .Required(True)
          .Schema(SWAG_INTEGER)
        .&End
        .AddResponse(404, 'Vendas não encontrado(a)').&End
        .AddResponse(400, 'BadRequest')
          .Schema(TAPIError)
        .&End
        .AddResponse(500).&End
      .&End
    .&End
  .&End

end.
