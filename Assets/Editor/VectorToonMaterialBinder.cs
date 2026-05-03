using System;
using System.Collections.Generic;
using System.IO;
using UnityEditor;
using UnityEngine;

public class VectorToonMaterialBinder : EditorWindow
{
    private const string DefaultFolder = "Assets/GirlsFrontline_Vector";
    private DefaultAsset targetFolder;
    private bool overwriteMaterials = true;
    private bool remapModelImporters = true;
    private bool assignSelectedRenderers = true;
    private Vector2 scrollPosition;

    private Shader bodyShader;
    private Shader faceShader;
    private Shader hairShader;
    private Shader eyeShader;

    private Texture2D cloth1Base;
    private Texture2D cloth1Normal;
    private Texture2D cloth1Rmo;
    private Texture2D cloth2Base;
    private Texture2D cloth2Normal;
    private Texture2D cloth2Rmo;
    private Texture2D weaponBase;
    private Texture2D weaponNormal;
    private Texture2D weaponRmo;
    private Texture2D faceBase;
    private Texture2D eyeBase;
    private Texture2D eyeBlend;
    private Texture2D hairBase;
    private Texture2D extraMap;
    private Texture2D skinRamp;
    private Texture2D hairSpa;
    private Texture2D shine1;
    private Texture2D shine2;

    [MenuItem("Tools/Vector Toon Material Binder")]
    public static void ShowWindow()
    {
        GetWindow<VectorToonMaterialBinder>("Vector Toon Binder");
    }

    private void OnEnable()
    {
        targetFolder = AssetDatabase.LoadAssetAtPath<DefaultAsset>(DefaultFolder);
        LoadShaders();
        AutoLoadTextures(DefaultFolder);
    }

    private void OnGUI()
    {
        GUILayout.Label("Vector Toon Material Binder", EditorStyles.boldLabel);
        EditorGUILayout.Space();

        targetFolder = (DefaultAsset)EditorGUILayout.ObjectField("Target Folder", targetFolder, typeof(DefaultAsset), false);
        overwriteMaterials = EditorGUILayout.Toggle("Overwrite Materials", overwriteMaterials);
        remapModelImporters = EditorGUILayout.Toggle("Remap FBX Materials", remapModelImporters);
        assignSelectedRenderers = EditorGUILayout.Toggle("Assign Selected Renderers", assignSelectedRenderers);

        EditorGUILayout.Space();

        if (GUILayout.Button("Reload Defaults"))
        {
            string folderPath = GetFolderPath();
            LoadShaders();
            AutoLoadTextures(folderPath);
        }

        if (GUILayout.Button("Bind Materials", GUILayout.Height(32)))
        {
            Bind();
        }

        scrollPosition = EditorGUILayout.BeginScrollView(scrollPosition);
        EditorGUILayout.Space();
        DrawShaderFields();
        EditorGUILayout.Space();
        DrawTextureFields();
        EditorGUILayout.EndScrollView();
    }

    private void DrawShaderFields()
    {
        GUILayout.Label("Shaders", EditorStyles.boldLabel);
        bodyShader = (Shader)EditorGUILayout.ObjectField("Body Shader", bodyShader, typeof(Shader), false);
        faceShader = (Shader)EditorGUILayout.ObjectField("Face Shader", faceShader, typeof(Shader), false);
        hairShader = (Shader)EditorGUILayout.ObjectField("Hair Shader", hairShader, typeof(Shader), false);
        eyeShader = (Shader)EditorGUILayout.ObjectField("Eye Shader", eyeShader, typeof(Shader), false);
    }

    private void DrawTextureFields()
    {
        GUILayout.Label("Textures", EditorStyles.boldLabel);
        cloth1Base = TextureField("Cloth1 Base", cloth1Base);
        cloth1Normal = TextureField("Cloth1 Normal", cloth1Normal);
        cloth1Rmo = TextureField("Cloth1 RMO", cloth1Rmo);
        cloth2Base = TextureField("Cloth2 Base", cloth2Base);
        cloth2Normal = TextureField("Cloth2 Normal", cloth2Normal);
        cloth2Rmo = TextureField("Cloth2 RMO", cloth2Rmo);
        weaponBase = TextureField("Weapon Base", weaponBase);
        weaponNormal = TextureField("Weapon Normal", weaponNormal);
        weaponRmo = TextureField("Weapon RMO", weaponRmo);
        faceBase = TextureField("Face Base", faceBase);
        eyeBase = TextureField("Eye Base", eyeBase);
        eyeBlend = TextureField("Eye Blend", eyeBlend);
        hairBase = TextureField("Hair Base", hairBase);
        extraMap = TextureField("Extra Atlas", extraMap);
        skinRamp = TextureField("Skin Ramp", skinRamp);
        hairSpa = TextureField("Hair SPA", hairSpa);
        shine1 = TextureField("Shine 1", shine1);
        shine2 = TextureField("Shine 2", shine2);
    }

    private Texture2D TextureField(string label, Texture2D texture)
    {
        return (Texture2D)EditorGUILayout.ObjectField(label, texture, typeof(Texture2D), false);
    }

    private void Bind()
    {
        string folderPath = GetFolderPath();
        if (string.IsNullOrEmpty(folderPath))
        {
            EditorUtility.DisplayDialog("Error", "Please assign a valid target folder.", "OK");
            return;
        }

        LoadShaders();
        if (!ValidateShaders())
            return;

        AutoLoadTextures(folderPath);
        string materialFolder = EnsureFolder(folderPath, "GeneratedToonMaterials");
        Dictionary<string, Material> materials = CreateMaterials(materialFolder);

        int remappedCount = remapModelImporters ? RemapModelMaterials(folderPath, materials) : 0;
        int assignedCount = assignSelectedRenderers ? AssignSelectedRenderers(materials) : 0;

        AssetDatabase.SaveAssets();
        AssetDatabase.Refresh();

        EditorUtility.DisplayDialog(
            "Done",
            $"Materials: {materials.Count}\nFBX remaps: {remappedCount}\nRenderer slots assigned: {assignedCount}",
            "OK"
        );
    }

    private string GetFolderPath()
    {
        if (targetFolder == null)
            return null;

        string folderPath = AssetDatabase.GetAssetPath(targetFolder);
        return AssetDatabase.IsValidFolder(folderPath) ? folderPath : null;
    }

    private void LoadShaders()
    {
        bodyShader = Shader.Find("Toon Shader/Toon_VectorBody");
        faceShader = Shader.Find("Toon Shader/Toon_VectorFace");
        hairShader = Shader.Find("Toon Shader/Toon_VectorHair");
        eyeShader = Shader.Find("Toon Shader/Toon_VectorEye");
    }

    private bool ValidateShaders()
    {
        List<string> missing = new List<string>();
        if (bodyShader == null) missing.Add("Toon Shader/Toon_VectorBody");
        if (faceShader == null) missing.Add("Toon Shader/Toon_VectorFace");
        if (hairShader == null) missing.Add("Toon Shader/Toon_VectorHair");
        if (eyeShader == null) missing.Add("Toon Shader/Toon_VectorEye");

        if (missing.Count == 0)
            return true;

        EditorUtility.DisplayDialog("Missing Shaders", string.Join("\n", missing), "OK");
        return false;
    }

    private void AutoLoadTextures(string folderPath)
    {
        if (string.IsNullOrEmpty(folderPath))
            return;

        cloth1Base = FindTexture(folderPath, "c_VectorSSR01_slg_cloth1_d");
        cloth1Normal = FindTexture(folderPath, "c_VectorSSR01_slg_cloth1_n");
        cloth1Rmo = FindTexture(folderPath, "c_vectorssr01_slg_cloth1_rmo");
        cloth2Base = FindTexture(folderPath, "c_VectorSSR01_slg_cloth2_d");
        cloth2Normal = FindTexture(folderPath, "c_VectorSSR01_slg_cloth2_n");
        cloth2Rmo = FindTexture(folderPath, "c_vectorssr01_slg_cloth2_rmo");
        weaponBase = FindTexture(folderPath, "c_VectorSSR01_slg_weapon_d");
        weaponNormal = FindTexture(folderPath, "c_VectorSSR01_slg_weapon_n");
        weaponRmo = FindTexture(folderPath, "c_vectorssr01_slg_weapon_rmo");
        faceBase = FindTexture(folderPath, "c_Vector_slg_face_d");
        eyeBase = FindTexture(folderPath, "c_Vector_slg_eye_d");
        eyeBlend = FindTexture(folderPath, "c_Vector_slg_eyeblend");
        hairBase = FindTexture(folderPath, "c_Vector_slg_hair_d");
        extraMap = FindTexture(folderPath, "extra");
        skinRamp = FindTexture(folderPath, "skintoon") ?? FindTexture(folderPath, "skin");
        hairSpa = FindTexture(folderPath, "hair0");
        shine1 = FindTexture(folderPath, "SSShine1");
        shine2 = FindTexture(folderPath, "SSShine2");
    }

    private Texture2D FindTexture(string folderPath, string nameStartsWith)
    {
        string[] guids = AssetDatabase.FindAssets("t:Texture2D", new[] { folderPath });
        foreach (string guid in guids)
        {
            string path = AssetDatabase.GUIDToAssetPath(guid);
            string name = Path.GetFileNameWithoutExtension(path);
            if (name.StartsWith(nameStartsWith, StringComparison.OrdinalIgnoreCase))
                return AssetDatabase.LoadAssetAtPath<Texture2D>(path);
        }

        return null;
    }

    private Dictionary<string, Material> CreateMaterials(string materialFolder)
    {
        Dictionary<string, Material> materials = new Dictionary<string, Material>(StringComparer.OrdinalIgnoreCase);

        Add(materials, "BodySkin", CreateOrUpdateMaterial(materialFolder, "BodySkin", faceShader, mat =>
        {
            SetFaceTextures(mat);
            SetFaceOverlay(mat, 0f, 0f);
        }));

        Add(materials, "Face", CreateOrUpdateMaterial(materialFolder, "Face", faceShader, mat =>
        {
            SetFaceTextures(mat);
            SetFaceOverlay(mat, 0f, 0f);
        }));

        Add(materials, "Brows", CreateOrUpdateMaterial(materialFolder, "Brows", faceShader, mat =>
        {
            SetFaceTextures(mat);
            SetFaceOverlay(mat, 0f, 0f);
            SetEyeThroughBlocker(mat, true);
            mat.SetColor("_Tint", new Color(0.28f, 0.22f, 0.2f, 1f));
        }));

        Add(materials, "Lashes", CreateOrUpdateMaterial(materialFolder, "Lashes", faceShader, mat =>
        {
            SetFaceTextures(mat);
            SetFaceOverlay(mat, 0f, 0f);
            SetEyeThroughBlocker(mat, true);
            mat.SetColor("_Tint", new Color(0.12f, 0.1f, 0.1f, 1f));
        }));

        Add(materials, "EyeLid", CreateOrUpdateMaterial(materialFolder, "EyeLid", faceShader, mat =>
        {
            SetAtlasCutoutTextures(mat);
            SetEyeThroughBlocker(mat, true);
        }));
        Add(materials, "EyeShadow", CreateOrUpdateMaterial(materialFolder, "EyeShadow", faceShader, mat =>
        {
            SetAtlasCutoutTextures(mat);
            SetEyeThroughBlocker(mat, true);
        }));
        Add(materials, "EyeWhite", CreateOrUpdateMaterial(materialFolder, "EyeWhite", faceShader, SetAtlasCutoutTextures));
        Add(materials, "Mouth", CreateOrUpdateMaterial(materialFolder, "Mouth", faceShader, SetAtlasCutoutTextures));
        Add(materials, "Tongue", CreateOrUpdateMaterial(materialFolder, "Tongue", faceShader, SetAtlasCutoutTextures));
        Add(materials, "Teeth", CreateOrUpdateMaterial(materialFolder, "Teeth", faceShader, SetAtlasCutoutTextures));
        Add(materials, "Teeth.001", CreateOrUpdateMaterial(materialFolder, "Teeth.001", faceShader, SetAtlasCutoutTextures));
        Add(materials, "Emotion1", CreateOrUpdateMaterial(materialFolder, "Emotion1", faceShader, SetAtlasCutoutTextures));
        Add(materials, "Emotion2", CreateOrUpdateMaterial(materialFolder, "Emotion2", faceShader, SetAtlasCutoutTextures));

        Add(materials, "Eyes", CreateOrUpdateMaterial(materialFolder, "Eyes", eyeShader, SetEyeTextures));
        Add(materials, "Eyes+", CreateOrUpdateMaterial(materialFolder, "Eyes+", eyeShader, mat =>
        {
            SetEyeTextures(mat);
            mat.SetTexture("_ShineMap", shine2 != null ? shine2 : shine1);
            mat.SetFloat("_ShineIntensity", 1.25f);
        }));

        Add(materials, "Hair", CreateOrUpdateMaterial(materialFolder, "Hair", hairShader, SetHairTextures));
        Add(materials, "Hair.001", CreateOrUpdateMaterial(materialFolder, "Hair.001", hairShader, SetHairTextures));
        Add(materials, "HairB2", CreateOrUpdateMaterial(materialFolder, "HairB2", hairShader, SetHairTextures));

        Add(materials, "Cloth1", CreateOrUpdateMaterial(materialFolder, "Cloth1", bodyShader, mat => SetBodyTextures(mat, cloth1Base, cloth1Normal, cloth1Rmo)));
        Add(materials, "Cloth2", CreateOrUpdateMaterial(materialFolder, "Cloth2", bodyShader, mat => SetBodyTextures(mat, cloth2Base, cloth2Normal, cloth2Rmo)));
        Add(materials, "Weapon", CreateOrUpdateMaterial(materialFolder, "Weapon", bodyShader, mat => SetBodyTextures(mat, weaponBase, weaponNormal, weaponRmo)));

        return materials;
    }

    private void Add(Dictionary<string, Material> materials, string key, Material material)
    {
        if (material != null)
            materials[key] = material;
    }

    private Material CreateOrUpdateMaterial(string folder, string materialName, Shader shader, Action<Material> setup)
    {
        string path = $"{folder}/{SanitizeFileName(materialName)}.mat";
        Material material = AssetDatabase.LoadAssetAtPath<Material>(path);

        if (material == null)
        {
            material = new Material(shader);
            material.name = materialName;
            AssetDatabase.CreateAsset(material, path);
        }
        else if (!overwriteMaterials)
        {
            return material;
        }

        material.shader = shader;
        setup?.Invoke(material);
        EditorUtility.SetDirty(material);
        return material;
    }

    private void SetBodyTextures(Material material, Texture2D baseMap, Texture2D normalMap, Texture2D rmoMap)
    {
        SetTexture(material, "_BaseMap", baseMap);
        SetTexture(material, "_NormalMap", normalMap);
        SetTexture(material, "_RMOMap", rmoMap);
        SetTexture(material, "_RampTex", skinRamp);
        material.SetFloat("_MetallicStrength", rmoMap != null ? 1f : 0f);
        material.SetFloat("_MatCapIntensity", 0f);
    }

    private void SetFaceTextures(Material material)
    {
        SetTexture(material, "_BaseMap", faceBase);
        SetTexture(material, "_SkinRampTex", skinRamp);
        SetTexture(material, "_EyeBlendMap", eyeBlend);
        SetTexture(material, "_ExtraMap", extraMap);
        SetFaceOverlay(material, 0f, 0f);
    }

    private void SetFaceOverlay(Material material, float eyeBlendIntensity, float extraIntensity)
    {
        SetFloat(material, "_EyeBlendIntensity", eyeBlendIntensity);
        SetFloat(material, "_ExtraIntensity", extraIntensity);
        SetFloat(material, "_AlphaClip", 0f);
        SetFloat(material, "_Cutoff", 0.5f);
        SetEyeThroughBlocker(material, false);
        material.SetOverrideTag("RenderType", "Opaque");
        material.renderQueue = -1;
    }

    private void SetAtlasCutoutTextures(Material material)
    {
        SetTexture(material, "_BaseMap", extraMap);
        SetTexture(material, "_SkinRampTex", skinRamp);
        SetTexture(material, "_EyeBlendMap", null);
        SetTexture(material, "_ExtraMap", null);
        SetFloat(material, "_EyeBlendIntensity", 0f);
        SetFloat(material, "_ExtraIntensity", 0f);
        SetFloat(material, "_AlphaClip", 1f);
        SetFloat(material, "_Cutoff", 0.2f);
        SetEyeThroughBlocker(material, false);
        material.SetOverrideTag("RenderType", "TransparentCutout");
        material.renderQueue = (int)UnityEngine.Rendering.RenderQueue.AlphaTest;
    }

    private void SetEyeThroughBlocker(Material material, bool enabled)
    {
        SetFloat(material, "_EyeThroughBlocker", enabled ? 1f : 0f);
    }

    private void SetHairTextures(Material material)
    {
        SetTexture(material, "_BaseMap", hairBase);
        SetTexture(material, "_NormalMap", null);
        SetTexture(material, "_HairMatCapMap", hairSpa);
        SetTexture(material, "_SpecMap", shine1);
        SetTexture(material, "_RampTex", skinRamp);
        material.SetFloat("_MatCapIntensity", hairSpa != null ? 0.65f : 0f);
        material.SetFloat("_SpecularStrength", shine1 != null ? 0.8f : 0f);
        SetFloat(material, "_ZWrite", 1f);
        material.renderQueue = -1;
    }

    private void SetEyeTextures(Material material)
    {
        SetTexture(material, "_BaseMap", eyeBase);
        SetTexture(material, "_EyeBlendMap", eyeBlend);
        SetTexture(material, "_ExtraMap", extraMap);
        SetTexture(material, "_ShineMap", shine1);
        SetFloat(material, "_EyeBlendIntensity", eyeBlend != null ? 0.85f : 0f);
        SetFloat(material, "_ExtraIntensity", 0f);
        material.SetFloat("_ShineIntensity", shine1 != null ? 1f : 0f);
        SetFloat(material, "_ZTest", (float)UnityEngine.Rendering.CompareFunction.LessEqual);
        SetFloat(material, "_ThroughHairIntensity", 0.45f);
        material.renderQueue = (int)UnityEngine.Rendering.RenderQueue.Geometry + 20;
    }

    private void SetTexture(Material material, string propertyName, Texture2D texture)
    {
        if (material.HasProperty(propertyName))
            material.SetTexture(propertyName, texture);
    }

    private void SetFloat(Material material, string propertyName, float value)
    {
        if (material.HasProperty(propertyName))
            material.SetFloat(propertyName, value);
    }

    private int RemapModelMaterials(string folderPath, Dictionary<string, Material> materials)
    {
        int count = 0;
        string[] modelGuids = AssetDatabase.FindAssets("t:Model", new[] { folderPath });

        foreach (string guid in modelGuids)
        {
            string modelPath = AssetDatabase.GUIDToAssetPath(guid);
            AssetImporter importer = AssetImporter.GetAtPath(modelPath);
            if (importer == null)
                continue;

            bool changed = false;
            foreach (UnityEngine.Object subAsset in AssetDatabase.LoadAllAssetRepresentationsAtPath(modelPath))
            {
                Material importedMaterial = subAsset as Material;
                if (importedMaterial == null)
                    continue;

                Material replacement = ResolveMaterial(importedMaterial.name, materials);
                if (replacement == null)
                    continue;

                importer.AddRemap(new AssetImporter.SourceAssetIdentifier(typeof(Material), importedMaterial.name), replacement);
                count++;
                changed = true;
            }

            if (changed)
                importer.SaveAndReimport();
        }

        return count;
    }

    private int AssignSelectedRenderers(Dictionary<string, Material> materials)
    {
        int count = 0;

        foreach (GameObject root in Selection.gameObjects)
        {
            Renderer[] renderers = root.GetComponentsInChildren<Renderer>(true);
            foreach (Renderer renderer in renderers)
            {
                Material[] sharedMaterials = renderer.sharedMaterials;
                bool changed = false;

                for (int i = 0; i < sharedMaterials.Length; i++)
                {
                    Material current = sharedMaterials[i];
                    if (current == null)
                        continue;

                    Material replacement = ResolveMaterial(current.name, materials);
                    if (replacement == null)
                        continue;

                    sharedMaterials[i] = replacement;
                    changed = true;
                    count++;
                }

                if (changed)
                {
                    renderer.sharedMaterials = sharedMaterials;
                    EditorUtility.SetDirty(renderer);
                }
            }
        }

        return count;
    }

    private Material ResolveMaterial(string materialName, Dictionary<string, Material> materials)
    {
        string normalized = NormalizeMaterialName(materialName);
        if (materials.TryGetValue(normalized, out Material exact))
            return exact;

        if (normalized.StartsWith("Cloth1", StringComparison.OrdinalIgnoreCase))
            return Get(materials, "Cloth1");
        if (normalized.StartsWith("Cloth2", StringComparison.OrdinalIgnoreCase))
            return Get(materials, "Cloth2");
        if (ContainsAny(normalized, "Weapon"))
            return Get(materials, "Weapon");
        if (ContainsAny(normalized, "Hair"))
            return Get(materials, "Hair");
        if (ContainsAny(normalized, "Eye") && !ContainsAny(normalized, "EyeLid", "EyeShadow", "EyeWhite"))
            return Get(materials, normalized.Contains("+") ? "Eyes+" : "Eyes");
        if (normalized.StartsWith("BodySkin", StringComparison.OrdinalIgnoreCase))
            return Get(materials, "BodySkin");
        if (normalized.StartsWith("Face", StringComparison.OrdinalIgnoreCase))
            return Get(materials, "Face");
        if (normalized.StartsWith("Brow", StringComparison.OrdinalIgnoreCase))
            return Get(materials, "Brows");
        if (normalized.StartsWith("Lash", StringComparison.OrdinalIgnoreCase))
            return Get(materials, "Lashes");
        if (normalized.StartsWith("Mouth", StringComparison.OrdinalIgnoreCase))
            return Get(materials, "Mouth");
        if (normalized.StartsWith("Tongue", StringComparison.OrdinalIgnoreCase))
            return Get(materials, "Tongue");
        if (normalized.StartsWith("Teeth.001", StringComparison.OrdinalIgnoreCase))
            return Get(materials, "Teeth.001");
        if (normalized.StartsWith("Teeth", StringComparison.OrdinalIgnoreCase))
            return Get(materials, "Teeth");
        if (normalized.StartsWith("Emotion1", StringComparison.OrdinalIgnoreCase))
            return Get(materials, "Emotion1");
        if (normalized.StartsWith("Emotion2", StringComparison.OrdinalIgnoreCase))
            return Get(materials, "Emotion2");
        if (normalized.StartsWith("EyeLid", StringComparison.OrdinalIgnoreCase))
            return Get(materials, "EyeLid");
        if (normalized.StartsWith("EyeShadow", StringComparison.OrdinalIgnoreCase))
            return Get(materials, "EyeShadow");
        if (normalized.StartsWith("EyeWhite", StringComparison.OrdinalIgnoreCase))
            return Get(materials, "EyeWhite");

        return null;
    }

    private Material Get(Dictionary<string, Material> materials, string key)
    {
        return materials.TryGetValue(key, out Material material) ? material : null;
    }

    private string NormalizeMaterialName(string materialName)
    {
        if (string.IsNullOrEmpty(materialName))
            return string.Empty;

        string name = materialName.Replace(" (Instance)", string.Empty).Trim();
        int generatedIndex = name.IndexOf("_Generated", StringComparison.OrdinalIgnoreCase);
        if (generatedIndex > 0)
            name = name.Substring(0, generatedIndex);
        return name;
    }

    private bool ContainsAny(string source, params string[] values)
    {
        foreach (string value in values)
        {
            if (source.IndexOf(value, StringComparison.OrdinalIgnoreCase) >= 0)
                return true;
        }
        return false;
    }

    private string EnsureFolder(string parentFolder, string folderName)
    {
        string path = $"{parentFolder}/{folderName}";
        if (!AssetDatabase.IsValidFolder(path))
            AssetDatabase.CreateFolder(parentFolder, folderName);
        return path;
    }

    private string SanitizeFileName(string name)
    {
        foreach (char c in Path.GetInvalidFileNameChars())
            name = name.Replace(c, '_');
        return name;
    }
}
