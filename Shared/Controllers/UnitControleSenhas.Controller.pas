unit UnitControleSenhas.Controller;

interface
uses
  Horse,
  Horse.Commons,
  Horse.GBSwagger,
  Classes,
  SysUtils,
  System.Json, UnitConstants;

type
  TControleSenhasController = class
    class procedure Router;
    class procedure Get(Req: THorseRequest; Res: THorseResponse; Next: TProc);
    class procedure Post(Req: THorseRequest; Res: THorseResponse; Next: TProc);
    class procedure Put(Req: THorseRequest; Res: THorseResponse; Next: TProc);
  end;

implementation

{ TControleSenhasController }

uses
  UnitConnection.Model.Interfaces,
  UnitDatabase,
  UnitFunctions,
  UnitTabela.Helpers;

class procedure TControleSenhasController.Get(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  oJson: TJSONObject;
begin
  oJson := TJSONObject.Create;
  oJson.AddPair('senha', TJSONNumber.Create(IncrementaGenerator('GEN_CONTROLE_SENHAS'))); 
  Res.Send<TJSONObject>(oJson);
end;

class procedure TControleSenhasController.Post(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var Query: iQuery;
begin
  Query := TDatabase.Query;
  Query.Add('SET GENERATOR GEN_CONTROLE_SENHAS TO 0');
  Query.ExecSQL;
  Res.Send<TJSONObject>(TJSONObject.Create.AddPair('msg', 'senha resetada com sucesso!'));
end;

class procedure TControleSenhasController.Put(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var Query: iQuery;
begin
  Query := TDatabase.Query;
  Query.Add('SET GENERATOR GEN_CONTROLE_SENHAS TO 0');
  Query.ExecSQL;
  Res.Send<TJSONObject>(TJSONObject.Create.AddPair('msg', 'senha resetada com sucesso!'));
end;

class procedure TControleSenhasController.Router;
begin
  THorse.Group
        .Prefix('/v1')
        .Route('/controle_senhas')
          .Get(Get)
          .Post(Post)
          .Put(Put)
        .&End
end;

type
	TControleSenhas = class
  private
    FSenha: string;
  published
    property Senha: string read FSenha write FSenha;
  end;

initialization
    Swagger
	.BasePath('v1')
    .Path('controle_senhas')
      .Tag('Controle Senhas')
      .GET('Obtem a senha', 'Obtem a senha')
        .AddResponse(200, 'Operação bem Sucedida')
          .Schema(TControleSenhas)
        .&End
        .AddResponse(400).&End
        .AddResponse(500).&End
      .&End
      .POST('Reseta a senha', 'Zera a senha')
        .AddResponse(200, 'Ok')
          .Schema('Senha resetada com sucesso!')
        .&End
        .AddResponse(400, 'BadRequest')
          .Schema(TAPIError)
        .&End
        .AddResponse(500).&End
      .&End
      .PUT('Reseta a senha', 'Zera a senha')
        .AddResponse(200, 'Ok')
          .Schema('Senha resetada com sucesso!')
        .&End
        .AddResponse(400, 'BadRequest')
          .Schema(TAPIError)
        .&End
        .AddResponse(500).&End
      .&End
    .&End
  .&End

end.
