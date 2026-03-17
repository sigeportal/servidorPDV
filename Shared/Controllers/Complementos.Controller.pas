unit Complementos.Controller;

interface
uses
  Horse,
  Horse.Commons,
  Horse.GBSwagger,
  Classes,
  SysUtils,
  System.Json,
  DB,
  UnitConnection.Model.Interfaces;


type
  TComplementosController = class
    class procedure Registrar;
    class procedure GetAdicionais(Req: THorseRequest; Res: THorseResponse; Next: TProc);
  end;

implementation

{ TComplementosController }

uses UnitConstants, UnitDatabase, UnitComplemento.Model;

class procedure TComplementosController.GetAdicionais(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Query    : iQuery;
  Categoria: string;
  aJson    : TJSONArray;
  oJson    : TJSONObject;
  Grupo: integer;
  SubGrupo: Integer;
begin
  if Req.Params.Count = 0 then
    raise Exception.Create('Parametro grupo é requerido!');
  Query := TDatabase.Query;
  SubGrupo := Req.Params.Items['subgrupo'].ToInteger;
  Query.Clear;
  Query.Add('SELECT GRU_G1 FROM GRUPOS WHERE GRU_CODIGO = :SUB_GRUPO');
  Query.AddParam('SUB_GRUPO', SubGrupo);
  Query.Open();
  if not Query.DataSet.IsEmpty then
  begin
    Grupo := Query.DataSet.FieldByName('GRU_G1').AsInteger;
    Query.Clear;
    Query.Add('SELECT ADI_CODIGO, ADI_NOME, ADI_VALOR FROM ADICIONAIS WHERE ADI_ESTADO = ''ATIVO'' AND ADI_G1 = :GRUPO');
    Query.AddParam('GRUPO', Grupo);
    Query.Open;
    aJson := TJSONArray.Create;
    Query.DataSet.First;
    while not Query.DataSet.Eof do
    begin
      oJson     := TJSONObject.Create;
      oJson.AddPair('codigo', TJSONNumber.Create(Query.DataSet.FieldByName('ADI_CODIGO').AsInteger));
      oJson.AddPair('nome', Query.DataSet.FieldByName('ADI_NOME').AsString);
      oJson.AddPair('valor', TJSONNumber.Create(Query.DataSet.FieldByName('ADI_VALOR').AsCurrency));
      aJson.AddElement(oJson);
      Query.DataSet.Next;
    end;
    Res.Send<TJSONArray>(aJson);
  end else
    Res.Send<TJSONObject>(TJSONObject.Create.AddPair('message', 'Categoria não encontrada')).Status(THTTPStatus.BadRequest);
end;

class procedure TComplementosController.Registrar;
begin
  THorse.Get('/v1/complementos/:subgrupo', GetAdicionais);
end;

initialization
  Swagger
    .Path('complementos')
      .Tag('complementos')
      .GET('Lista Adicionais por Subgrupo', 'Retorna os adicionais associados a um subgrupo')
        .AddParamPath('subgrupo', 'Codigo do subgrupo')
          .Required(True)
          .Schema(SWAG_INTEGER)
        .&End
        .AddResponse(200, 'Operação bem sucedida')
          .Schema(TModelComplemento)
          .IsArray(True)
        .&End
        .AddResponse(400).&End
        .AddResponse(500).&End
      .&End
    .&End
  .&End

end.
