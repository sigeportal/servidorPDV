unit Mesas.Controller;

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
  DataSet.Serialize;

type
  TMesasController = class
    class procedure Registrar;
    class procedure Get(Req: THorseRequest; Res: THorseResponse; Next: TProc);
    class procedure GetMesa(Req: THorseRequest; Res: THorseResponse; Next: TProc);
    class procedure Post(Req: THorseRequest; Res: THorseResponse; Next: TProc);
    class procedure Put(Req: THorseRequest; Res: THorseResponse; Next: TProc);
    class procedure CriaMesa(Req: THorseRequest; Res: THorseResponse);
  end;

implementation

{ TMesasController }

uses UnitConstants, UnitDatabase;

class procedure TMesasController.CriaMesa(Req: THorseRequest; Res: THorseResponse);
var
  oJson: TJSONObject;
  Query: iQuery;
begin
	oJson := Req.Body<TJSONObject>;
  try
  	Query := TDatabase.Query;
    Query.Clear;
    Query.Add('UPDATE OR INSERT INTO MESAS (MES_CODIGO, MES_NOME, MES_ESTADO)');
    Query.Add('VALUES (:CODIGO, :NOME, :ESTADO)');
    Query.Add('MATCHING (MES_CODIGO)');    
    Query.AddParam('CODIGO', oJson.GetValue<integer>('codigo', 0));
    Query.AddParam('NOME', oJson.GetValue<string>('nome', ''));
    Query.AddParam('ESTADO', oJson.GetValue<string>('estado', 'A'));
    Query.ExecSQL;
    Res.Send<TJSONObject>(oJson).Status(THTTPStatus.OK);
  except on E: Exception do
    raise Exception.Create('Erro ao tentar mudar inserir mesa '+sLineBreak+E.Message);
  end;
end;

class procedure TMesasController.Get(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Query: iQuery;
  Dados: TDataSource;
begin
  Dados := TDataSource.Create(nil);
  Query := TDatabase.Query;
  Query.Clear;
  Query.Open('SELECT M.*, COM_VALOR MES_VALOR FROM MESAS M LEFT JOIN COMANDAS ON COM_MESA = MES_CODIGO AND COM_DATA_FECHAMENTO IS NULL');
  Dados.DataSet := Query.DataSet;
  Res.Send<TJSONArray>(Dados.DataSet.ToJSONArray);
end;

class procedure TMesasController.GetMesa(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Query: iQuery;
  Dados: TDataSource;
  CodMesa: Integer;
begin
  if Req.Params.Count > 0 then
  begin
    CodMesa := Req.Params.Items['codigo'].ToInteger();
    Dados := TDataSource.Create(nil);
    Query := TDatabase.Query;
    Query.Clear;
    Query.Add('SELECT M.*, COM_VALOR MES_VALOR FROM MESAS M LEFT JOIN COMANDAS ON COM_MESA = MES_CODIGO AND COM_DATA_FECHAMENTO IS NULL WHERE MES_CODIGO = :CODIGO');
    Query.AddParam('CODIGO', CodMesa);
    Query.Open();
    Dados.DataSet := Query.DataSet;
    Res.Send<TJSONObject>(Dados.DataSet.ToJSONObject);
  end else
    Res.Send(TJSONObject.Create.AddPair('error', 'Codigo da mesa não informado')).Status(THTTPStatus.BadRequest);
end;

class procedure TMesasController.Post(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Query: iQuery;
  Codigo: Integer;
  Status: string;
begin
  Query := TDatabase.Query;
  if Req.Params.ContainsKey('codigo') then
    Codigo := Req.Params['codigo'].ToInteger();
  if Req.Params.ContainsKey('status') then
    Status := Req.Params['status'];
  // Atualiza o estado da mesa
  try
    Query.Clear;
    Query.Add('UPDATE MESAS SET MES_ESTADO = :STATUS WHERE MES_CODIGO = :CODIGO');
    Query.AddParam('CODIGO', Codigo);
    Query.AddParam('STATUS', Status);
    Query.ExecSQL;
    Res.Send<TJSONObject>(TJSONObject.Create.AddPair('status', Status)).Status(THTTPStatus.OK);
  except on E: Exception do
    raise Exception.Create('Erro ao tentar mudar status da mesa '+Codigo.ToString+sLineBreak+E.Message);
  end;
end;

class procedure TMesasController.Put(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Query: iQuery;
  Codigo: Integer;
  JsonObj: TJSONObject;
  Estado, Nome: string;
begin
  if not Req.Params.ContainsKey('codigo') then
  begin
    Res.Send(TJSONObject.Create.AddPair('error', 'Codigo da mesa não informado')).Status(THTTPStatus.BadRequest);
    Exit;
  end;
  Codigo := Req.Params.Items['codigo'].ToInteger;
  Query := TDatabase.Query;
  try
    JsonObj := TJSONObject.ParseJSONValue(Req.Body) as TJSONObject;
    try
      // Atualiza apenas os campos informados no JSON
      Query.Clear;
      Query.Add('UPDATE MESAS SET ');
      Estado := '';
      Nome := '';
      if Assigned(JsonObj) then
      begin
        if JsonObj.GetValue('estado') <> nil then
          Estado := JsonObj.GetValue('estado').Value;
        if JsonObj.GetValue('nome') <> nil then
          Nome := JsonObj.GetValue('nome').Value;
      end;
      if (Estado.IsEmpty) and (Nome.IsEmpty) then
      begin
        Res.Send(TJSONObject.Create.AddPair('error', 'Nenhum campo para atualizar')).Status(THTTPStatus.BadRequest);
        Exit;
      end;
      // Monta SQL dinâmico
      if not Estado.IsEmpty then
      begin
        Query.Add('MES_ESTADO = :ESTADO');
        Query.AddParam('ESTADO', Estado);
      end;
      if not Nome.IsEmpty then
      begin
        if not Estado.IsEmpty then
          Query.Add(', MES_NOME = :NOME')
        else
          Query.Add('MES_NOME = :NOME');
        Query.AddParam('NOME', Nome);
      end;
      Query.Add('WHERE MES_CODIGO = :CODIGO');
      Query.AddParam('CODIGO', Codigo);
      Query.ExecSQL;
      Res.Send<TJSONObject>(TJSONObject.Create.AddPair('codigo', TJSONNumber.Create(Codigo))).Status(THTTPStatus.OK);
    finally
      JsonObj.Free;
    end;
  except on E: Exception do
    Res.Send(TJSONObject.Create.AddPair('error', E.Message)).Status(THTTPStatus.InternalServerError);
  end;
end;

class procedure TMesasController.Registrar;
begin
  THorse.Get('/v1/mesas', Get);
  THorse.Post('/v1/mesas', CriaMesa);
  THorse.Post('/v1/mesas/:codigo/status/:status', Post);
  THorse.Get('/v1/mesas/:codigo', GetMesa);
  THorse.Put('/v1/mesas/:codigo', Put);
end;

type
  TMesaSchema = class
  private
    FCodigo: Integer;
    FNome: string;
    FEstado: string;
    FValor: Currency;
  published
    property codigo: Integer read FCodigo write FCodigo;
    property nome: string read FNome write FNome;
    property estado: string read FEstado write FEstado;
  end;

initialization
  Swagger
    // Lista e criacao/atualizacao via parametros
    .Path('mesas')
      .Tag('mesas')
      .GET('Lista Mesas', 'Lista todas as mesas')
        .AddResponse(200, 'Operação bem sucedida').&End
        .AddResponse(400).&End
        .AddResponse(500).&End
      .&End
      .POST('Cria mesas', 'Cria mesas recebe um json no body')        
      	.AddParamBody('Mesa', 'Json da criação de mesa')
        	.Required(true)
        	.Schema(TMesaSchema)
        .&End
        .AddResponse(200, 'Ok').&End
        .AddResponse(400).&End
        .AddResponse(500).&End
      .&End
    .&End
    
    .Path('mesas/{codigo}/status/{status}')
      .Tag('mesas')
      .POST('Atualiza status da mesa', 'Atualiza o status da mesa via parametros de path')
        .AddParamPath('codigo', 'Codigo da mesa').Required(True).Schema(SWAG_INTEGER).&End
        .AddParamPath('status', 'Novo status da mesa').Required(True).Schema(SWAG_STRING).&End
        .AddResponse(200, 'Ok').&End
        .AddResponse(400).&End
        .AddResponse(500).&End
      .&End
    .&End

    // Operacoes que usam codigo no path
    .Path('mesas/{codigo}')
      .Tag('mesas')
      .GET('Obtem Mesa por codigo', 'Retorna os dados de uma mesa por codigo')
        .AddParamPath('codigo', 'Codigo da mesa')
          .Required(True)
          .Schema(SWAG_INTEGER)
        .&End
        .AddResponse(200, 'Operação bem sucedida').&End
        .AddResponse(400).&End
        .AddResponse(500).&End
      .&End
      .PUT('Atualiza dados da mesa', 'Atualiza campos da mesa via JSON no body')
        .AddParamPath('codigo', 'Codigo da mesa')
          .Required(True)
          .Schema(SWAG_INTEGER)
        .&End
        .AddParamBody('Dados da Mesa', 'Mesa').Required(False).Schema(TMesaSchema).&End
        .AddResponse(200, 'Ok').&End
        .AddResponse(400).&End
        .AddResponse(500).&End
      .&End
    .&End
  .&End

end.
